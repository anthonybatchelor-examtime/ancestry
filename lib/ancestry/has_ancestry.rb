class << ActiveRecord::Base
  def has_ancestry options = {}
    # Check options
    raise Ancestry::AncestryException.new(I18n.t("ancestry.option_must_be_hash")) unless options.is_a? Hash
    options.each do |key, value|
      unless [:ancestry_column, :orphan_strategy, :cache_depth, :depth_cache_column].include? key
        raise Ancestry::AncestryException.new(I18n.t("ancestry.unknown_option", {:key => key.inspect, :value => value.inspect}))
      end
    end

    # Include instance methods
    include Ancestry::InstanceMethods

    # Include dynamic class methods
    extend Ancestry::ClassMethods

    # Create ancestry column accessor and set to option or default
    cattr_accessor :ancestry_column
    self.ancestry_column = options[:ancestry_column] || :ancestry

    # Create orphan strategy accessor and set to option or default (writer comes from DynamicClassMethods)
    cattr_reader :orphan_strategy
    self.orphan_strategy = options[:orphan_strategy] || :destroy

    # Save self as base class (for STI)
    cattr_accessor :base_class
    self.base_class = self

    # Validate format of ancestry column value
    validates_format_of ancestry_column, :with => Ancestry::ANCESTRY_PATTERN, :allow_nil => true

    # Validate that the ancestor ids don't include own id
    validate :ancestry_exclude_self

    # Named scopes
    scope :roots, :conditions => {ancestry_column => nil}
    scope :ancestors_of, lambda { |object| {:conditions => to_node(object).ancestor_conditions} }
    scope :children_of, lambda { |object| {:conditions => to_node(object).child_conditions} }
    scope :descendants_of, lambda { |object| {:conditions => to_node(object).descendant_conditions} }
    scope :subtree_of, lambda { |object| {:conditions => to_node(object).subtree_conditions} }
    scope :siblings_of, lambda { |object| {:conditions => to_node(object).sibling_conditions} }
    scope :ordered_by_ancestry, reorder("(case when #{table_name}.#{ancestry_column} is null then 0 else 1 end), #{table_name}.#{ancestry_column}")
    scope :ordered_by_ancestry_and, lambda { |order| reorder("(case when #{table_name}.#{ancestry_column} is null then 0 else 1 end), #{table_name}.#{ancestry_column}, #{order}") }

    # Update descendants with new ancestry before save
    before_save :update_descendants_with_new_ancestry

    # Apply orphan strategy before destroy
    before_destroy :apply_orphan_strategy

    # Create ancestry column accessor and set to option or default
    if options[:cache_depth]
      # Create accessor for column name and set to option or default
      self.cattr_accessor :depth_cache_column
      self.depth_cache_column = options[:depth_cache_column] || :ancestry_depth

      # Cache depth in depth cache column before save
      before_validation :cache_depth

      # Validate depth column
      validates_numericality_of depth_cache_column, :greater_than_or_equal_to => 0, :only_integer => true, :allow_nil => false
    end

    # Create named scopes for depth
    {:before_depth => '<', :to_depth => '<=', :at_depth => '=', :from_depth => '>=', :after_depth => '>'}.each do |scope_name, operator|
      scope scope_name, lambda { |depth|
        raise Ancestry::AncestryException.new(I18n.t("ancestry.named_scope_depth_cache",
                                                     {
                                                       :scope_name => scope_name
                                                     })) unless options[:cache_depth]
        {:conditions => ["#{depth_cache_column} #{operator} ?", depth]}
      }
    end
  end

  # Alias has_ancestry with acts_as_tree, if it's available.
  if !defined?(ActsAsTree)
    alias_method :acts_as_tree, :has_ancestry
  end
end
