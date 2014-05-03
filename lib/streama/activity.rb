module Streama
  module Activity
    extend ActiveSupport::Concern

    included do

      include Mongoid::Document
      include Mongoid::Timestamps

      field :verb,          :type => Symbol
      field :actor
      field :object
      field :target_object
      field :receivers,     :type => Array

      #index({ 'actor._id' => 1, 'actor._type' => 1 })
      #index({ 'actor.l' => "2d"}, {min: -200, max: 200, background: true, sparse: true})
      index({ 'object.id' => 1})
      index({ 'target_object.id' => 1}, sparse: true)
      index({ 'updated_at' => 1})
      index({ 'object.expires' => 1}, sparse: true)
      index({ 'object.flagged' => 1}, sparse: true)
      index({ 'receivers' => 1}, {background: true})
      index({ 'verb' => 1, 'object.id' => 1}, sparse: true)

      validates_presence_of :actor, :verb
      before_save :assign_data
      after_destroy :update_group

      belongs_to :group, {class_name: 'Streama::GroupRepresentative', inverse_of: :activities}
      index({group_id: 1}, {sparse: true})  # using a custom index instead of normal foreign_key index because of sparse requirement

    end

    module ClassMethods

      # Defines a new activity type and registers a definition
      #
      # @param [ String ] name The name of the activity
      #
      # @example Define a new activity
      #   activity(:enquiry) do
      #     actor :user, :cache => [:full_name]
      #     object :enquiry, :cache => [:subject]
      #     target_object :listing, :cache => [:title]
      #   end
      #
      # @return [Definition] Returns the registered definition
      def activity(name, &block)
        definition = Streama::DefinitionDSL.new(name)
        definition.instance_eval(&block)
        Streama::Definition.register(definition)
      end

      # Publishes an activity using an activity name and data
      #
      # @param [ String ] verb The verb of the activity
      # @param [ Hash ] data The data to initialize the activity with.
      #
      # @return [Streama::Activity] An Activity instance with data
      def publish(verb, data)
        receivers = data.delete(:receivers)
        new({:verb => verb}.merge(data)).publish(:receivers => receivers)
      end

      def stream_for(actor, options={})
        query = {:receivers => {'$elemMatch' => {:id => actor.id, :type => actor.class.to_s}}}
        query.merge!({:verb.in => [*options[:type]]}) if options[:type]
        self.where(query).without(:receivers).desc(:created_at)
      end

      def stream_of(actor, options={})
         query = {'actor.id' => actor.id, 'actor.type' => actor.class.to_s}
         query.merge!({:verb.in => [*options[:type]]}) if options[:type]
         self.where(query).without(:receivers).desc(:created_at)
      end

    end


    # Publishes the activity to the receivers
    #
    # @param [ Hash ] options The options to publish with.
    #
    def publish(options = {})
      actor = load_instance(:actor)
      self.receivers = (options[:receivers] || actor.followers).map { |r| { :id => r.id, :type => r.class.to_s } }
      self.ensure_grouping
      self.save
      self
    end

    # groups the activity under a owner (owner's representative)
    # if possible
    def ensure_grouping
      owner = self.group_owner
      if owner.nil?
        # nothing to do ... the activity is not groupable
        return
      end

      # get the representative of the group
      rep = owner.group_representative ||
            owner.create_group_representative()

      # set the rep as the self.group if not already set
      if self.group!=rep
        self.group = rep
        self.save!
      end

      # update the last_activity of the rep
      rep.set(:last_activity, self.cached_view)
      # NOTE the reciever field is indexed and can grow to be VERY LARGE
      # but since writes are fire and forget and indexing is backgrounded
      # it seems safe to blindly add ALL the current activities receivers to the rep
      rep.add_to_set(:receivers, {'$each' => self.receivers})
      rep.touch
    end

    # Returns an instance of an actor, object or target
    #
    # @param [ Symbol ] type The data type (actor, object, target) to return an instance for.
    #
    # @return [Mongoid::Document] document A mongoid document instance
    def load_instance(type)
      (data = self.read_attribute(type)).is_a?(Hash) ? data['type'].to_s.camelcase.constantize.find(data['id']) : data
    end

    def refresh_data
      assign_data
      save(:validates_presence_of => false)
    end

    def group_owner
      owner_type = definition.group_under
      load_instance(owner_type)
    end

    def cached_view
      {'_id' => self.id.to_s,
        'verb' => self.verb,
        'actor' => self.actor,
        'object' => self.object,
        'target_object' => self.target_object,
        'created_at' => self.created_at}
    end

    protected

    def assign_data

      [:actor, :object, :target_object].each do |type|
        next unless object = load_instance(type)

        class_sym = object.class.name.underscore.to_sym

        raise Errors::InvalidData.new(class_sym) unless definition.send(type).has_key?(class_sym)

        hash = {'id' => object.id, 'type' => object.class.name}

        if fields = definition.send(type)[class_sym].try(:[],:cache)
          fields.each do |field|
            raise Errors::InvalidField.new(field) unless object.respond_to?(field)
            hash[field.to_s] = object.send(field)
          end
        end
        write_attribute(type, hash)
      end
    end

    def update_group
      rep = self.group

      if rep.nil? || self.id.to_s!=rep.last_activity['_id']
        return
      end

      # if this is the last_activity in the rep's record
      # then update the rep with an alternate last_activity
      alt = rep.activities.desc(:created_at).first
      if !alt.nil?
        rep.set(:last_activity, alt.cached_view)
        rep.set(:updated_at, alt.created_at)
      else
        rep.destroy
      end
    end

    def definition
      @definition ||= Streama::Definition.find(verb)
    end

  end
end
