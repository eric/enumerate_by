require 'acts_as_enumeration/extensions/associations'
require 'acts_as_enumeration/extensions/base_conditions'
require 'acts_as_enumeration/extensions/serializer'
require 'acts_as_enumeration/extensions/xml_serializer'

module PluginAWeek #:nodoc:
  # An enumeration defines a finite set of identifiers which (often) have no
  # numerical order.  This plugin provides a general technique for using
  # ActiveRecord classes to define enumerations.
  # 
  # == Defining enumerations
  # 
  # To define a model as an enumeration:
  # 
  #   class Color < ActiveRecord::Base
  #     acts_as_enumeration
  #   end
  # 
  # This will create the class/instance methods for accessing the enumeration
  # identifiers.
  # 
  # == Defining identifiers
  # 
  # Identifiers represent the individual values within the enumeration.
  # Enumerations +do not+ have a database backing.  Instead, the records are
  # all created and maintained within the enumeration class.  For example,
  # 
  #   class Color < ActiveRecord::Base
  #     acts_as_enumeration
  #     
  #     create :id => 1, :name => 'red'
  #     create :id => 2, :name => 'blue'
  #     create :id => 3, :name => 'green'
  #   end
  # 
  # There are certain restrictions on what types of queries can be run on this
  # type of enumeration, but it should be sufficient with support for queries
  # by attribute, e.g. Color.find_by_name('red')
  # 
  # == Accessing enumeration identifiers
  # 
  # The actual records for an enumeration identifier can be accessed by id or
  # name:
  # 
  #   Color[1]      # => #<Color id: 1, name: "red">
  #   Color['red']  # => #<Color id: 1, name: "red">
  # 
  # These records are cached, so there is no performance hit and the same object
  # can be compared against itself, i.e. Color[1] == Color['red']
  # 
  # == Custom-identified enumerations
  # 
  # Sometimes you may need to create enumerations that are based on an attribute
  # other than +name+.  For example,
  # 
  #   class Book
  #     acts_as_enumeration :title
  #     
  #     create :id => 1, :title => 'Blink'
  #   end
  # 
  # This will create enumerations identified by the +title+ attribute instead of
  # the commonly used +name+ attribute.  This attribute will also determine what
  # values are indexed for the enumeration's lookup identifiers.  In this case,
  # records can be accessed by id or title:
  # 
  #   Book[1]        # => #<Book id: 1, title: "Blink">
  #   Book['Blink']  # => #<Book id: 1, title: "Blink">
  # 
  # == Additional enumeration attributes
  # 
  # In addition to the attribute used to identify an enumeration identifier, you
  # can also define additional attributes just like regular ActiveRecord models:
  # 
  #   class Book < ActiveRecord::Base
  #     acts_as_enumeration :title
  #     
  #     column :author, :string
  #     column :num_pages, :integer
  #     
  #     validates_presence_of :author
  #     validates_numericality_of :num_pages
  #     
  #     create :id => 1, :title => 'Blink', :author => 'Malcolm Gladwell', :num_pages => 277
  #   end
  # 
  # These attributes are exactly like normal ActiveRecord attributes:
  # 
  #   Book['Blink']   # => #<Book id: 1, title: "Blink", author: "Malcolm Gladwell", num_pages: 277>
  module ActsAsEnumeration #:nodoc:
    mattr_accessor :connection
    
    def self.included(base) #:nodoc:
      base.class_eval do
        # Tracks which attributes represent enumerations
        class_inheritable_accessor :enumeration_associations
        self.enumeration_associations = {}
        
        extend PluginAWeek::ActsAsEnumeration::MacroMethods
      end
    end
    
    # Stores shared db connections
    class Enumeration < ActiveRecord::Base
      self.connection = {
        :adapter => 'sqlite3',
        :database => ':memory:',
        :verbose => 'quiet'
      }
    end
    
    module MacroMethods
      # Indicates that this class should be representative of an enumeration.
      # 
      # The default attribute used to reference a unique identifier is +name+.
      # You can override this by specifying a custom attribute that will be
      # used to uniquely reference a particular identifier. See PluginAWeek::ActsAsEnumeration
      # for more information.
      # 
      # == Attributes
      # 
      # The following columns are automatically generated for the model:
      # * +id+ - The unique id for a recrod
      # * <tt>#{attribute}</tt> - The unique attribute specified
      # 
      # == Validations
      # 
      # In addition to the default columns, default validations are generated
      # to ensure the presence of the default attributes and that the
      # identifier attribute is unique across all records.
      def acts_as_enumeration(attribute = :name)
        attribute = attribute.to_s
        
        clear_active_connection_name
        @active_connection_name = 'PluginAWeek::ActsAsEnumeration::Enumeration'
        
        connection.create_table(table_name) do |t|
          t.string attribute
        end
        connection.add_index table_name, attribute, :unique => true
        
        # A list of the unique attributes defining an enumerated value
        write_inheritable_attribute :enumeration_attribute, attribute
        class_inheritable_reader :enumeration_attribute
        
        write_inheritable_attribute :enumeration_column_names, %w(id #{attribute})
        class_inheritable_reader :enumeration_column_names
        
        # A cache of the records that have been created
        cattr_accessor :records
        self.records = {}
        
        validates_presence_of   :id
        validates_presence_of   attribute
        validates_uniqueness_of attribute
        
        extend PluginAWeek::ActsAsEnumeration::ClassMethods
        include PluginAWeek::ActsAsEnumeration::InstanceMethods
      end
      
      # Is this class an enumeration?
      def enumeration?
        false
      end
    end
    
    module ClassMethods
      def self.extended(base) #:nodoc:
        class << base
          alias_method_chain :has_many, :enumerations
          alias_method_chain :has_one, :enumerations
          alias_method_chain :sanitize_sql_hash_for_conditions, :symbolic_enumeration_attributes
          
          # Don't allow silent failures
          alias_method :create, :create!
        end
      end
      
      # Defines a new column in the model.  The following defaults are defined:
      # * +sql_type+ - None; any value allowed
      # * +default+ - No default
      # * +null+ - Allow null values
      def column(name, sql_type = nil, default = nil, null = true)
        # Remove any existing columns with the same name
        connection.remove_column table_name, name if enumeration_column_names.any? {|column_name| column_name == name.to_s}
        
        connection.add_column table_name, name, sql_type, :default => default, :null => null
        enumeration_column_names << name
        
        attr_readonly name
      end
      
      # Uses the cached record instead of instantiating a new one
      def instantiate(record)
        records[record['id']]
      end
      
      # Adds support for automatically reloading has_many associations
      def has_many_with_enumerations(association_id, options = {}, &extension)
        has_many_without_enumerations(association_id, options, &extension)
        enumeration_accessor_methods_with_fresh_cache(association_id)
      end
      
      # Adds support for automatically reloading has_one associations
      def has_one_with_enumerations(association_id, options = {})
        has_one_without_enumerations(association_id, options)
        enumeration_accessor_methods_with_fresh_cache(association_id)
      end
      
      # Automatically clears association cache for non-enumerations
      def enumeration_accessor_methods_with_fresh_cache(association_id) #:nodoc:
        reflection = reflections[association_id.to_sym]
        if !Object.const_defined?(reflection.class_name) || !reflection.klass.enumeration?
          name = reflection.name
          class_name = reflection.class_name
          
          define_method("#{name}_with_fresh_cache") do
            value = send("#{name}_without_fresh_cache")
            instance_variable_set("@#{name}", nil) unless reflection.klass.enumeration? # Get rid of the cached value
            value
          end
          alias_method_chain name, :fresh_cache
        end
      end
      
      # Looks up the corresponding enumeration record.  You can lookup the
      # following types:
      # * +fixnum+ - The id of the record
      # * +string+ - The value of the identifier attribute
      # * +symbol+ - The symbolic value of the identifier attribute
      # 
      # If you do not want to worry about exceptions, then use +find_by_id+ or
      # +<tt>find_by_#{attribute}</tt>, where attribute is the identifier attribute
      # specified when calling +acts_as_enumeration+.
      # 
      # == Examples
      # 
      #   class Book < ActiveRecord::Base
      #     acts_as_enumeration :title
      #     
      #     create :id => 1, :title => 'Blink'
      #   end
      # 
      #   Book[1]         # => #<Book id: 1, title: "Blink">
      #   Book['Blink']   # => #<Book id: 1, title: "Blink">
      #   Book[:Blink]    # => #<Book id: 1, title: "Blink">
      #   Book[2]         # => ActiveRecord::RecordNotFound: Couldn't find Book with value(s) 2
      #   Book['Invalid'] # => ActiveRecord::RecordNotFound: Couldn't find Book with value(s) "Invalid"
      def [](value)
        find_by_any(value) || raise(ActiveRecord::RecordNotFound, "Couldn't find #{name} with value #{value.inspect}")
      end
      
      # Finds the enumerated value indicated by the given value or returns nil
      # if nothing was found. The value can be any one of the following types:
      # * +fixnum+ - The id of the record
      # * +string+ - The value of the identifier attribute
      # * +symbol+ - The symbolic value of the identifier attribute
      def find_by_any(value)
        if value.is_a?(Fixnum)
          find_by_id(value)
        else
          find_by_enumeration_attribute(value)
        end
      end
      
      # Finds the record that matches the enumeration's identifer attribute for
      # the given value. The attribute is based on what was specified when calling
      # +acts_as_enumeration+.
      def find_by_enumeration_attribute(value)
        send("find_by_#{enumeration_attribute}", value)
      end
      
      # Add support for the conditions hash for conditions
      def sanitize_sql_hash_for_conditions_with_symbolic_enumeration_attributes(attrs)
        attrs.each do |attr, value|
          attrs[attr] = value.to_s if value.is_a?(Symbol) && attr.to_s == enumeration_attribute
        end
        
        sanitize_sql_hash_for_conditions_without_symbolic_enumeration_attributes(attrs)
      end
      
      # Is this class an enumeration?  This value is used to determine when
      # +belongs_to+, +has_one+, and +has_many+ associations should using the
      # enumeration interface instead of going through ActiveRecord.
      def enumeration?
        true
      end
    end
    
    # Many of the ActiveRecord features are removed from enumerations to improve
    # performance for enumerations with a large number of values (e.g. countries
    # or regions).  These features include:
    # * Dirty tracking - Tracks when attribute values have changed for a record
    # * Callbacks - Allows other code to hook into the save/update/destroy/etc. process
    # 
    # These features do not provide any particular benefit for runtime usage when
    # used with enumerations, since enumerations should not be dynamic during
    # the runtime.
    # 
    # == Equality
    # 
    # It's important to note that there *is* support for performing equality
    # comparisons with other objects based on the value of the enumeration's
    # identifier attribute specified when calling +acts_as_enumeration+.  This
    # is useful for case statements or when used within view helpers like
    # +collection_select+
    # 
    # For example,
    # 
    #   class Book < ActiveRecord::Base
    #     acts_as_enumeration :title
    #     
    #     create :id => 1, :title => 'Blink'
    #   end
    # 
    #   Book[1] == 1              # => true
    #   1 == Book[1]              # => true
    #   Book['Blink'] == 'Blink'  # => true
    #   'Blink' == Book['Blink']  # => true
    #   Book['Blink'] == Blink[1] # => true
    module InstanceMethods
      def self.included(base) #:nodoc:
        base.class_eval do
          # Disable unused ActiveRecord features
          {:callbacks => %w(create_or_update create valid?), :dirty => %w(write_attribute save save! reload)}.each do |feature, methods|
            methods.each do |method|
              method, punctuation = method.sub(/([?!=])$/, ''), $1
              alias_method "#{method}#{punctuation}", "#{method}_without_#{feature}#{punctuation}"
            end
          end
          
          alias_method_chain :create, :cache
          alias_method_chain :destroy, :cache
        end
      end
      
      # Enumeration values should never really be destroyed during runtime.
      # However, this is supported to complete the full circle for an record's
      # liftime in ActiveRecord
      def destroy_with_cache #:nodoc:
        value = destroy_without_cache
        remove_from_cache
        value
      end
      
      # Whether or not this enumeration is equal to the given value. Equality
      # is based on the following types:
      # * +fixnum+ - The id of the record
      # * +string+ - The value of the identifier attribute
      # * +symbol+ - The symbolic value of the identifier attribute
      def ==(arg)
        case arg
        when String, Fixnum, Symbol
          self == self.class.find_by_any(arg)
        else
          super
        end
      end
      
      # Determines whether this enumeration is in the given list
      def in?(*list)
        list.any? {|item| self === item}
      end
      
      # The current value for the enumeration attribute
      def enumeration_value
        send("#{enumeration_attribute}")
      end
      
      # Stringifies the enumeration attributes
      def to_s
        to_str
      end
      
      # Add support for equality comparison with strings
      def to_str
        enumeration_value
      end
      
      private
        # Creates the record, caching it for future access
        def create_with_cache
          value = create_without_cache
          readonly!
          add_to_cache
          value
        end
        
        # Records the record in the cache
        def add_to_cache
          self.class.records[id.to_s] = self
        end
        
        # Removes the cached record
        def remove_from_cache
          self.class.records.delete(id.to_s)
        end
        
        # Allow id to be assigned via ActiveRecord::Base#attributes=
        def attributes_protected_by_default #:nodoc:
          []
        end
    end
  end
end

ActiveRecord::Base.class_eval do
  include PluginAWeek::ActsAsEnumeration
end
