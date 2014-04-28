module Streama

  class GroupRepresentative
    include Mongoid::Document
    include Mongoid::Timestamps::Updated

    field :hidden,    {type: Boolean, default: false}
    field :recievers, {type: Array, default: []}
    field :last_activity, {type: Hash, default: {}}

    belongs_to :tangible, {polymorphic: true, index: true}
    has_many   :activities, {class_name: 'Activity', inverse_of: :group}

    index({hidden: 1, recievers: 1}, {background: true})
    index({updated_at: 1})
  end

end

