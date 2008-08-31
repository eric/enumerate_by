module PluginAWeek #:nodoc:
  module ActsAsEnumeration
    module Extensions #:nodoc:
      # Adds auto-generated methods for any belongs_to/has_one/has_many enumeration
      # associations.  For example,
      # 
      #   class Color < ActiveRecord::Base
      #     acts_as_enumeration
      #     
      #     create :id => 1, :name => 'red'
      #     create :id => 2, :name => 'blue'
      #     create :id => 3, :name => 'green'
      #   end
      #   
      #   class Car < ActiveRecord::Base
      #     belongs_to :color
      #   end
      # 
      # will auto-generate named scopes for the Color enumeration like so:
      # 
      #   red_cars = Car.with_color('red')
      #   blue_car = Car.with_color('blue')
      #   red_and_blue_cars = Car.with_colors('red', 'blue')
      # 
      # In addition to these named scopes, this adds support for setting enumeration
      # associations using the enumeration attribute.  For example,
      # 
      #   car = Car.find(1)
      #   car.color = 'red'
      #   car.save
      #   car.color   # => #<Color id: 1, name: "red">
      # 
      # == has_one/has_many
      # 
      # In addition to belongs_to, you can also define has_one/has_many associations
      # with other regular or enumeration models.  For example,
      # 
      #   class ColorGroup < ActiveRecord::Base
      #     acts_as_enumeration
      #     
      #     has_many :colors, :foreign_key => 'group_id'
      #     
      #     create :id => 1, :name => 'RGB'
      #     create :id => 2, :name => 'CMYK'
      #   end
      #   
      #   class Color < ActiveRecord::Base
      #     acts_as_enumeration
      #     
      #     column :group_id, :integer
      #     
      #     belongs_to :group, :class_name => 'ColorGroup'
      #     has_many :cars
      #   end
      #   
      #   class Car < ActiveRecord::Base
      #     belongs_to :color
      #   end
      module Associations
        def self.extended(base) #:nodoc:
          class << base
            alias_method_chain :belongs_to, :enumerations
          end
        end
        
        # Adds support for belongs_to and enumerations
        def belongs_to_with_enumerations(association_id, options = {})
          belongs_to_without_enumerations(association_id, options)
          
          # Override accessor if class is already defined
          reflection = reflections[association_id.to_sym]
          
          if !reflection.options[:polymorphic] && reflection.klass.enumeration?
            name = reflection.name
            primary_key_name = reflection.primary_key_name
            class_name = reflection.class_name
            klass = reflection.klass
            
            # Add generic scopes that can have enumeration identifiers passed in
            %W(with_#{name} with_#{name.to_s.pluralize}).each do |scope_name|
              named_scope scope_name.to_sym, Proc.new {|*identifiers| {
                :conditions => {primary_key_name => identifiers.flatten.collect {|identifier| klass[identifier].id}}
              }}
            end
            
            # Support looking up the enumeration by string, symbol, or id
            define_method("#{name}_with_enumerations=") do |new_value|
              send("#{name}_without_enumerations=", new_value.is_a?(klass) ? new_value : klass.find_by_any(new_value))
            end
            alias_method_chain "#{name}=", :enumerations
            
            # Track the association
            enumeration_associations[primary_key_name] = name.to_s
          end
        end
      end
    end
  end
end

ActiveRecord::Base.class_eval do
  extend PluginAWeek::ActsAsEnumeration::Extensions::Associations
end
