module Streama
  
  module Actor
    extend ActiveSupport::Concern

    included do
      raise Errors::NotMongoid, "Must be included in a Mongoid::Document" unless self.ancestors.include? Mongoid::Document
      
      cattr_accessor :activity_klass
    end

    module ClassMethods
          
      def activity_class(klass)
        self.activity_klass = klass.to_s
      end
      
    end

    # Publishes the activity to the receivers
    #
    # @param [ Hash ] options The options to publish with.
    #
    # @example publish an activity with a object and target
    #   current_user.publish_activity(:enquiry, :object => @enquiry, :target => @listing)
    #
    def publish_activity(name, options={})
      options[:receivers] = self.send(options[:receivers]) if options[:receivers].is_a?(Symbol)
      activity = activity_class.publish(name, {:actor => self}.merge(options))
    end
  
    def activity_stream(options = {})
      activity_class.stream_for(self, options)
    end
    
    def published_activities(options = {})
      activity_class.stream_of(self, options)
    end
    
    def activity_class
      @activity_klass ||= activity_klass ? activity_klass.classify.constantize : ::Activity
    end
  end 
  
end