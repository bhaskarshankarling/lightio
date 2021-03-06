require 'socket'

module LightIO::Module
  extend Base::NewHelper

  define_new_for_modules *%w{Addrinfo Socket IPSocket TCPSocket TCPServer UDPSocket UNIXSocket UNIXServer}

  module Addrinfo
    include LightIO::Module::Base

    module WrapperHelper
      protected
      def wrap_class_addrinfo_return_method(method)
        define_method method do |*args|
          result = __send__(:"origin_#{method}", *args)
          if result.is_a?(::Addrinfo)
            wrap_to_library(result)
          elsif result.respond_to?(:map)
            result.map {|r| wrap_to_library(r)}
          else
            result
          end
        end
      end

      def wrap_class_addrinfo_return_methods(*methods)
        methods.each {|m| wrap_class_addrinfo_return_method(m)}
      end
    end

    module ClassMethods
      include LightIO::Module::Base::Helper
      extend WrapperHelper

      def foreach(*args, &block)
        LightIO::Library::Addrinfo.getaddrinfo(*args).each(&block)
      end

      wrap_class_addrinfo_return_methods :getaddrinfo, :ip, :udp, :tcp, :unix
    end
  end

  module BasicSocket
    include LightIO::Module::Base

    module ClassMethods
      include LightIO::Module::Base::Helper

      def for_fd(fd)
        wrap_to_library(origin_for_fd(fd))
      end
    end
  end

  module Socket
    include LightIO::Module::Base

    module ClassMethods
      include LightIO::Module::Base::Helper
      extend LightIO::Wrap::Wrapper::HelperMethods
      ## implement ::Socket class methods
      wrap_methods_run_in_threads_pool :getaddrinfo, :gethostbyaddr, :gethostbyname, :gethostname,
                                       :getnameinfo, :getservbyname

      def getifaddrs
        origin_getifaddrs.map {|ifaddr| LightIO::Library::Socket::Ifaddr._wrap(ifaddr)}
      end

      def socketpair(domain, type, protocol)
        origin_socketpair(domain, type, protocol).map {|s| wrap_to_library(s)}
      end

      alias_method :pair, :socketpair

      def unix_server_socket(path)
        if block_given?
          origin_unix_server_socket(path) {|s| yield wrap_to_library(s)}
        else
          wrap_to_library(origin_unix_server_socket(path))
        end
      end

      def ip_sockets_port0(ai_list, reuseaddr)
        origin_ip_sockets_port0(ai_list, reuseaddr).map {|s| wrap_to_library(s)}
      end
    end
  end


  module IPSocket
    include LightIO::Module::Base

    module ClassMethods
      extend LightIO::Wrap::Wrapper::HelperMethods
      wrap_methods_run_in_threads_pool :getaddress
    end
  end

  module TCPSocket
    include LightIO::Module::Base
  end

  module TCPServer
    include LightIO::Module::Base
  end

  module UDPSocket
    include LightIO::Module::Base
  end

  module UNIXSocket
    include LightIO::Module::Base

    module ClassMethods
      include LightIO::Module::Base::Helper

      def socketpair(*args)
        origin_socketpair(*args).map {|io| wrap_to_library(io)}
      end

      alias_method :pair, :socketpair
    end
  end

  module UNIXServer
    include LightIO::Module::Base
  end
end
