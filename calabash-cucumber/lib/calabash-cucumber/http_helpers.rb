require 'httpclient'

module Calabash
  module Cucumber

    # @!visibility private
    module HTTPHelpers

      require 'calabash-cucumber/environment'

      # @!visibility private
      CAL_HTTP_RETRY_COUNT=3

      # @!visibility private
      RETRYABLE_ERRORS = [HTTPClient::TimeoutError,
                          HTTPClient::KeepAliveDisconnected,
                          Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED,
                          Errno::ETIMEDOUT]

      # @!visibility private
      def http(options, data=nil)
        _private_dismiss_springboard_alerts

        options[:uri] = url_for(options[:path])
        options[:method] = options[:method] || :get
        if data
          if options[:raw]
            options[:body] = data
          else
            options[:body] = data.to_json
          end
        end
        res = Timeout.timeout(45) do
          make_http_request(options)
        end
        res.force_encoding('UTF-8') if res.respond_to?(:force_encoding)

        _private_dismiss_springboard_alerts

        res
      rescue Timeout::Error
        raise Timeout::Error, 'The http call to Calabash web-server has timed out. It may mean that your app has crashed or frozen'
      end

      # @!visibility private
      def url_for(verb)
        url = URI.parse(Calabash::Cucumber::Environment.device_endpoint)
        path = url.path
        if path.end_with? '/'
          path = "#{path}#{verb}"
        else
          path = "#{path}/#{verb}"
        end
        url.path = path
        url
      end

      # @!visibility private
      def make_http_request(options)
        retryable_errors = options[:retryable_errors] || RETRYABLE_ERRORS
        CAL_HTTP_RETRY_COUNT.times do |count|
          begin
            if not @http
              @http = init_request(options)
            end

            response = if options[:method] == :post
              @http.post(options[:uri], options[:body])
            else
              @http.get(options[:uri], options[:body])
            end

            raise Errno::ECONNREFUSED if response.status_code == 502

            return response.body
          rescue => e

            if retryable_errors.include?(e) || retryable_errors.any? { |c| e.is_a?(c) }

              if count < CAL_HTTP_RETRY_COUNT-1
                if e.is_a?(HTTPClient::TimeoutError)
                  sleep(3)
                else
                  sleep(0.5)
                end
                @http.reset_all
                @http=nil
                STDOUT.write "Retrying.. #{e.class}: (#{e})\n"
                STDOUT.flush
              else
                puts "Failing... #{e.class}"
                raise e
              end
            else
              raise e
            end
          end
        end
      end

      # @!visibility private
      def init_request(options={})
        http = HTTPClient.new
        http.connect_timeout = 5
        http.send_timeout = 15
        http.receive_timeout = 15
        if options[:debug] || (ENV['DEBUG_HTTP'] == '1' && options[:debug] != false)
          http.debug_dev = $stdout
        end
        http
      end

      private

      # @!visibility private
      #
      # Do not call this method.
      def _private_dismiss_springboard_alerts
        require 'calabash-cucumber/launcher'
        launcher = Calabash::Cucumber::Launcher.launcher_if_used
        if launcher && launcher.automator && launcher.automator.name == :device_agent
          launcher.automator.client.send(:_dismiss_springboard_alerts)
        end
      end
    end
  end
end
