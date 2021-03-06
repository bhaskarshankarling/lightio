require 'thread'
require_relative 'queue'

module LightIO::Library
  class ThreadGroup
    include Base
    include LightIO::Wrap::Wrapper
    mock ::ThreadGroup

    def add(thread)
      if @obj.enclosed?
        raise ThreadError, "can't move from the enclosed thread group"
      elsif thread.is_a?(LightIO::Library::Thread)
        # let thread decide how to add to group
        thread.send(:add_to_group, self)
      else
        @obj.add(thread)
      end
      self
    end

    def list
      @obj.list + threads
    end

    private
    def threads
      @threads ||= []
    end

    Default = ThreadGroup._wrap(::ThreadGroup::Default)
  end


  class Thread
    # constants
    ThreadError = ::ThreadError
    Queue = LightIO::Library::Queue
    Backtrace = ::Thread::Backtrace
    SizedQueue = LightIO::Library::SizedQueue

    extend Base::MockMethods
    mock ::Thread

    extend LightIO::Module::Thread::ClassMethods
    extend Forwardable

    def initialize(*args, &blk)
      init_core(*args, &blk)
    end

    def_delegators :@beam, :alive?, :value

    def_delegators :"Thread.main",
                   :abort_on_exception,
                   :abort_on_exception=,
                   :pending_interrupt?,
                   :add_trace_func,
                   :backtrace,
                   :backtrace_locations,
                   :priority,
                   :priority=,
                   :safe_level

    def kill
      @beam.kill && self
    end

    alias exit kill
    alias terminate kill

    def status
      if self.class.current == self
        'run'
      elsif alive?
        @beam.error.nil? ? 'sleep' : 'abouting'
      else
        @beam.error.nil? ? false : nil
      end
    end

    def thread_variables
      thread_values.keys
    end

    def thread_variable_get(name)
      thread_values[name.to_sym]
    end

    def thread_variable_set(name, value)
      thread_values[name.to_sym] = value
    end

    def thread_variable?(key)
      thread_values.key?(key)
    end

    def [](name)
      fiber_values[name.to_sym]
    end

    def []=(name, val)
      fiber_values[name.to_sym] = val
    end

    def group
      @group
    end

    def inspect
      "#<LightIO::Library::Thread:0x00#{object_id.to_s(16)} #{status}>"
    end

    def join(limit=nil)
      @beam.join(limit) && self
    end

    def key?(sym)
      fiber_values.has_key?(sym)
    end

    def keys
      fiber_values.keys
    end

    def raise(exception, message=nil, backtrace=nil)
      @beam.raise(LightIO::Beam::BeamError.new(exception), message, backtrace)
    end

    def run
      Kernel.raise ThreadError, 'killed thread' unless alive?
      Thread.pass
    end

    alias wakeup run

    def stop?
      !alive? || status == 'sleep'
    end

    private
    def init_core(*args, &blk)
      @beam = LightIO::Beam.new(*args, &blk)
      @beam.on_dead = proc {on_dead}
      @beam.on_transfer = proc {|from, to| on_transfer(from, to)}
      # register this thread
      thread_values
      # add self to ThreadGroup::Default
      add_to_group(LightIO::Library::ThreadGroup::Default)
      # remove thread and thread variables
      ObjectSpace.define_finalizer(self, LightIO::Library::Thread.finalizer(self.object_id))
    end

    # add self to thread group
    def add_to_group(group)
      # remove from old group
      remove_from_group
      @group = group
      @group.send(:threads) << self
    end

    # remove thread from group when dead
    def remove_from_group
      @group.send(:threads).delete(self) if @group
    end

    def on_dead
      # release references
      remove_from_group
    end

    def on_transfer(from, to)
      Thread.instance_variable_set(:@current_thread, self)
    end

    def thread_values
      Thread.send(:threads)[object_id] ||= {}
    end

    def fibers_and_values
      @fibers_and_values ||= {}
    end

    def fiber_values
      beam_or_fiber = LightIO::Beam.current
      # only consider non-root fiber
      if !beam_or_fiber.instance_of?(::Fiber) || LightIO::LightFiber.is_root?(beam_or_fiber)
        beam_or_fiber = @beam
      end
      fibers_and_values[beam_or_fiber] ||= {}
    end

    class << self
      extend Forwardable
      def_delegators :'::Thread',
                     :DEBUG,
                     :DEBUG=,
                     :handle_interrupt,
                     :abort_on_exception,
                     :abort_on_exception=,
                     :pending_interrupt?

      def method_missing(*args)
        ::Thread.__send__(*args)
      end

      def respond_to?(*args)
        ::Thread.respond_to?(*args)
      end

      def respond_to_missing?(method, *)
        ::Thread.respond_to?(method)
      end

      private

      # threads and threads variables
      def threads
        thrs = Thread.instance_variable_get(:@threads)
        thrs || Thread.instance_variable_set(:@threads, {})
      end

      def thread_mutex
        mutex = Thread.instance_variable_get(:@thread_mutex)
        mutex || Thread.instance_variable_set(:@thread_mutex, LightIO::Library::Mutex.new)
      end
    end

    class Mutex
      extend Base::MockMethods
      mock ::Mutex

      def initialize
        @queue = LightIO::Library::Queue.new
        @queue << true
        @locked_thread = nil
      end

      def lock
        raise ThreadError, "deadlock; recursive locking" if owned?
        @queue.pop
        @locked_thread = LightIO::Thread.current
        self
      end

      def unlock
        raise ThreadError, "Attempt to unlock a mutex which is not locked" unless owned?
        @locked_thread = nil
        @queue << true
        self
      end

      def locked?
        !@locked_thread.nil?
      end

      def owned?
        @locked_thread == LightIO::Thread.current
      end

      def sleep(timeout=nil)
        unlock
        LightIO.sleep(timeout)
        lock
      end

      def synchronize
        raise ThreadError, 'must be called with a block' unless block_given?
        lock
        begin
          yield
        ensure
          unlock
        end
      end

      def try_lock
        if @locked_thread.nil?
          lock
          true
        else
          false
        end
      end
    end

    class ConditionVariable
      extend Base::MockMethods
      mock ::ConditionVariable

      def initialize
        @queue = LightIO::Library::Queue.new
      end


      def broadcast
        signal until @queue.num_waiting == 0
        self
      end

      def signal
        @queue << true unless @queue.num_waiting == 0
        self
      end

      def wait(mutex, timeout=nil)
        mutex.unlock
        begin
          LightIO::Library::Timeout.timeout(timeout) do
            @queue.pop
          end
        rescue Timeout::Error
          nil
        end
        mutex.lock
        self
      end
    end
  end

  Mutex = Thread::Mutex
  ConditionVariable = Thread::ConditionVariable
end
