module LightIO::Wrap
  WRAPPERS = {}
  RAW_IO = ::IO

  # wrapper for normal ruby objects
  module Wrapper
    # wrap raw ruby objects
    #
    # @param [Object] io raw ruby object, param name is 'io' just for consistent
    def initialize(io=nil)
      @io ||= io
    end

    def method_missing(method, *args)
      @io.public_send(method, *args)
    end

    # both works in class scope and singleton class scope
    module SingletonClassCommonMethods
      protected
      # run method in thread pool for performance
      def wrap_methods_run_in_threads_pool(*args)
        #TODO
      end
    end

    module ClassMethods
      # Wrap raw io objects
      def _wrap(io)
        # In case ruby stdlib return already patched Sockets, just do nothing
        if io.is_a? self
          io
        else
          # old new
          obj = allocate
          obj.send(:initialize, io)
          obj
        end
      end

      # override new method, return wrapped class
      def new(*args)
        io = raw_class.new(*args)
        _wrap(io)
      end

      include SingletonClassCommonMethods

      protected

      attr_reader :raw_class

      # Set wrapped class
      def wrap(raw_class)
        @raw_class=raw_class
        WRAPPERS[raw_class] = self
      end

      def method_missing(method, *args)
        raw_class.public_send(method, *args)
      end
    end

    class << self
      def included(base)
        base.send :extend, ClassMethods
        base.singleton_class.send :extend, SingletonClassCommonMethods
      end
    end
  end

  # wrapper for ruby io objects
  module IOWrapper
    include Wrapper
    # wrap raw ruby io objects
    #
    # @param [IO, Socket]  io raw ruby io object
    def initialize(io=nil)
      super
      @io_watcher ||= LightIO::Watchers::IO.new(@io)
    end

    protected
    # wait io nonblock method
    #
    # @param [Symbol]  method method name, example: wait_nonblock
    # @param [args] args arguments pass to method
    def wait_nonblock(method, *args)
      loop do
        result = @io.__send__(method, *args, exception: false)
        case result
          when :wait_readable
            @io_watcher.wait_readable
          when :wait_writable
            @io_watcher.wait_writable
          else
            return result
        end
      end
    end

    module ClassMethods
      include Wrapper::ClassMethods
      protected
      # wrap blocking method with "#{method}_nonblock"
      #
      # @param [Symbol]  method method name, example: wait
      def wrap_blocking_method(method)
        define_method method do |*args|
          wait_nonblock(:"#{method}_nonblock", *args)
        end
      end

      def wrap_blocking_methods(*methods)
        methods.each {|m| wrap_blocking_method(m)}
      end
    end

    class << self
      def included(base)
        Wrapper.included(base)
        base.send :extend, ClassMethods
      end
    end
  end
end