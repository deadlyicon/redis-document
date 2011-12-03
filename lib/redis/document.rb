require 'redis'
require 'redis/namespace'
require 'redis/document/version'
require 'uuid'
require 'active_support'
require 'active_support/concern'
require 'active_support/buffered_logger'
require 'active_support/core_ext/benchmark'

require 'active_model'

module Redis::Document

  extend ActiveSupport::Concern

  class << self

    def redis
      @redis or self.redis = ::Redis.current and @redis
    end
    attr_writer :redis

    def logger= logger
      @logger = logger.respond_to?(:info) ? logger : ActiveSupport::BufferedLogger.new(logger)
    end

    def logger
      @logger or self.logger = STDOUT and @logger
    end

  end

  included do
    extend ActiveModel::Callbacks
    define_model_callbacks :save, :delete
  end

  module ClassMethods

    def redis= redis
      @redis = Redis::Namespace.new(name, :redis => redis)
    end

    def redis
      @redis or self.redis = Redis::Document.redis and @redis
    end

    def keys
      @keys ||= []
      @keys + (superclass.respond_to?(:keys) ? superclass.keys : [])
    end

    def key name
      @keys ||= []
      return if @keys.include? name
      @keys << name
      class_eval <<-RUBY, __FILE__, __LINE__
        def #{name}
          read_key "#{name}"
        end
        def #{name}= value
          write_key "#{name}", value
        end
      RUBY
    end

    def find id
      benchmark(:find, id){
        document = new
        document.instance_variable_set(:@id, id)
        document.new_record? ? nil : document
      }
    end

    def all
      redis.keys.map{ |id| find id }
    end

    def benchmark action, id=nil
      name = id.nil? ? self.name : "#{self.name}(#{id})"
      result = nil
      ms = Benchmark.ms { result = yield }
      Redis::Document.logger.info('%s %s (%.1fms)' % [ name, action, ms ])
      result
    end

  end

  module InstanceMethods

    def initialize id=nil
      @id = id
    end

    def id
      @id ||= UUID.generate
    end

    def read_key key
      cache[key.to_s]
    end

    def write_key key, value
      key = key.to_s
      return false if cache[key] == value
      cache[key] = value
      _set_(key, Marshal.dump(value))
      @new_record = false
      true
    end

    def new_record?
      @new_record = !_exists_ if @new_record.nil?
      @new_record
    end
    alias_method :exists?, :new_record?

    def keys
      self.class.keys
    end

    def inspect
      content = ["id: #{id}"] + keys.map{|key| "#{key}: #{read_key(key).inspect}"}
      "#<#{self.class} #{content.join(', ')}>"
    end

    def reload
      @cache = nil or cache and self
    end

    def benchmark action, &block
      self.class.benchmark(action, id, &block)
    end

    protected

    def cache
      @cache ||= _get_.inject({}){ |cache,(field,value)| cache.update field => Marshal.load(value) }
    end

    def _get_
      return {} if @new_record == true
      benchmark(:load){ self.class.redis.hgetall(id) }
    end

    def _set_ key, value
      benchmark("write :#{key}"){ self.class.redis.hset(id, key, value) }
    end

    def _exists_
      benchmark(:exists?){ self.class.redis.exists(id) }
    end
  end



end
