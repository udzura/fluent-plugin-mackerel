module Fluent
  class MackerelOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('mackerel', self)

    config_param :api_key, :string
    config_param :hostid, :string, :default => nil
    config_param :hostid_path, :string, :default => nil
    config_param :metrics_prefix, :string
    config_param :out_keys, :string

    config_param :flush_interval, :time, :default => 1

    attr_reader :mackerel

    # Define `log` method for v0.10.42 or earlier
    unless method_defined?(:log)
      define_method("log") { $log }
    end

    def initialize
      super
    end

    def configure(conf)
      super

      @mackerel = Mackerel.new(conf['api_key'])
      @out_keys = @out_keys.split(',')

      if @hostid.nil? and @hostid_path.nil?
        raise Fluent::ConfigError, "Either 'hostid' or 'hostid_path' must be specifed."
      end

      unless @hostid_path.nil?
        @hostid = File.open(@hostid_path).read
      end

    end

    def start
      super
    end

    def shutdown
      super
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      metrics = []
      chunk.msgpack_each do |(tag,time,record)|
        out_keys.map do |key|
          metrics << {
            'hostId' => @hostid,
            'value' => record[key].to_f,
            'time' => time,
            'name' => "%s.%s" % [@metrics_prefix, key]
          }
        end
      end

      begin
        @mackerel.post_metrics(metrics)
      rescue => e
        log.error("out_mackerel:", :error_class => e.class, :error => e.message)
      end
    end

  end

  class Mackerel

    USER_AGENT = "fluent-plugin-mackerel Ruby/#{RUBY_VERSION}"

    def initialize(api_key)
      require 'net/http'
      require 'json'

      @api_key = api_key
      @http = Net::HTTP.new('mackerel.io', 443)
      @http.use_ssl = true
    end

    def post_metrics(metrics)
      req = Net::HTTP::Post.new('/api/v0/tsdb', initheader = {
        'X-Api-Key' => @api_key,
        'Content-Type' =>'application/json',
        'User-Agent' => USER_AGENT
      })
      req.body = metrics.to_json
      res = @http.request(req)

      if res.is_a?(Net::HTTPUnauthorized)
        raise MackerelError, "invalid api key used. check api_key in your configuration."
      end

      unless res and res.is_a?(Net::HTTPSuccess)
        raise MackerelError, "failed to post, code: #{res.code}"
      end
    end

  end

  class MackerelError < RuntimeError; end

end