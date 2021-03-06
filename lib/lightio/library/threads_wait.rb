require 'thwait'

module LightIO::Library
  class ThreadsWait
    ErrNoWaitingThread = ::ThreadsWait::ErrNoWaitingThread
    ErrNoFinishedThread = ::ThreadsWait::ErrNoFinishedThread

    extend Base::MockMethods
    mock ::ThreadsWait

    extend LightIO::Module::ThreadsWait::ClassMethods

    attr_reader :threads

    def initialize(*threads)
      @threads = threads
    end

    def all_waits
      until empty?
        thr = next_wait
        yield thr if block_given?
      end
    end

    def empty?
      @threads.empty?
    end

    def finished?
      @threads.any? {|thr| !thr.alive?}
    end

    def join(*threads)
      join_nowait(*threads)
      next_wait
    end

    def join_nowait(*threads)
      @threads.concat(threads)
    end

    def next_wait(nonblock=nil)
      raise ::ThreadsWait::ErrNoWaitingThread, 'No threads for waiting.' if empty?
      @threads.each do |thr|
        if thr.alive? && nonblock
          next
        elsif thr.alive?
          thr.join
        end
        # thr should dead
        @threads.delete(thr)
        return thr
      end
      raise ::ThreadsWait::ErrNoFinishedThread, 'No finished threads.'
    end
  end
end
