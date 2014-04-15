require 'rdf'
require 'ldp'
require 'ldp_monkeypatch'
require 'rdf/turtle'
require 'nokogiri'
require 'active_model'
require 'active_support/concern'
require 'active_support/core_ext/object'
require 'active_support/core_ext/class/attribute'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/hash'
require 'fedora_lens/errors'

module FedoraLens
  extend ActiveSupport::Concern
  extend ActiveSupport::Autoload
  autoload :AttributeMethods

  module AttributeMethods
    extend ActiveSupport::Autoload

    eager_autoload do
      autoload :Read
      autoload :Write
    end
  end

  HOST = "http://localhost:8983/fedora"
  #HOST = "http://localhost:8080"
  PATH = '/rest'

  def self.connection
    @@connection ||= Ldp::Client.new(HOST)
  end

  included do
    extend ActiveModel::Naming
    include ActiveModel::Validations
    include ActiveModel::Conversion
    include FedoraLens::AttributeMethods

    attr_reader :orm
  end

  def initialize(subject_or_data = {}, data = nil)
    init_core(subject_or_data, data)
  end

  def persisted?()      false end

  def errors
    obj = Object.new
    def obj.[](key)         [] end
    def obj.full_messages() [] end
    obj
  end

  def read_attribute_for_validation(key)
    @attributes[key]
  end

  def reload
    @orm = @orm.reload
    @attributes = get_attributes_from_orm(@orm)
  end

  def delete
    @orm.resource.delete
  end

  def save
    new_record? ? create_record : update_record
  end

  def save!
    save || raise(RecordNotSaved)
  end

  def new_record?
    @new_record
  end

  def uri
    @orm.try(:resource).try(:subject_uri).try(:to_s)
  end

  def id
    URI.parse(uri).to_s.sub(HOST + PATH, '') if uri.present?
  end

  protected
    # This allows you to overide the initializer, but still use this behavior
    def init_core(subject_or_data = {}, data = nil)
      @new_record = true
      case subject_or_data
        when Ldp::Resource
          @orm = Ldp::Orm.new(subject_or_data)
          @attributes = get_attributes_from_orm(@orm)
        when NilClass, Hash
          data = subject_or_data || {}
          @orm = Ldp::Orm.new(Ldp::Resource.new(FedoraLens.connection, nil, RDF::Graph.new))
          @attributes = data.with_indifferent_access
        when String
          data ||= {}
          @orm = Ldp::Orm.new(Ldp::Resource.new(FedoraLens.connection, subject_or_data, RDF::Graph.new))
          @attributes = data.with_indifferent_access
        else
          raise ArgumentError, "#{data.class} is not acceptable"
        end
    end

    def create_record
      push_attributes_to_orm
      orm.resource.create
      @new_record = false
      true
    end

    def update_record
      push_attributes_to_orm
      # Fedora errors out when you try to set the rdf:type
      # see https://github.com/cbeer/ldp/issues/2
      orm.graph.delete([@orm.resource.subject_uri,
                         RDF::URI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
                         nil])
      orm.save
      orm.last_response.success?
    end


  private

  def push_attributes_to_orm
    @orm = self.class.orm_to_hash.put(@orm, @attributes)
  end

  def get_attributes_from_orm(orm)
    self.class.orm_to_hash.get(orm).with_indifferent_access
  end

  module ClassMethods
    def find(id)
      resource = Ldp::Resource.new(FedoraLens.connection, id_to_uri(id))
      self.new(resource)
    end

    def id_to_uri(id)
      "#{HOST}#{PATH}#{id}"
    end

    def create(data)
      model = self.new(data)
      model.save
      model
    end

    def orm_to_hash
      if @orm_to_hash.nil?
        aggregate_lens = attributes_as_lenses.reduce({}) do |acc, pair|
          name, path = pair
          lens = path.reduce {|outer, inner| Lenses.compose(outer, inner)}
          acc.merge(name => lens)
        end
        @orm_to_hash = Lenses.orm_to_hash(aggregate_lens)
      end
      @orm_to_hash
    end

    # def has_one(name, scope = nil, options = {})
    #   ActiveRecord::Associations::Builder::HasOne.build(self, name, scope, options)
    # end
  end
end

require 'fedora_lens/lenses'
