module Streama
  
  module GroupOwner
    extend ActiveSupport::Concern

    included do
      raise Errors::NotMongoid, "Must be included in a Mongoid::Document" unless self.ancestors.include? Mongoid::Document

      has_one :group_representative, {class_name: 'Streama::GroupRepresentative', as: :tangible, dependent: :destroy}
    end

    def grouped_activities
      self.group_representative.try :activities
    end

    def hide_activity_group
      self.group_representative.try do |rep|
        rep.set(:hidden, true)
      end
    end

    def unhide_activity_group
      self.group_representative.try do |rep|
        rep.set(:hidden, false)
      end
    end

  end

end

