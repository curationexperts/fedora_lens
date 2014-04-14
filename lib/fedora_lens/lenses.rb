require 'fedora_lens/lens'

module FedoraLens
  module Lenses
    # We would like to use lenses like this: Lenses.at_css.get(...)
    # Using a simple hash is gross because calls are like this: Lenses.at_css[:get].call(...)
    # If we use a Module, we can't pass in parameters to build a more specific lens like
    # in the case of the at_css lens.
    # If we use a class, we need to call it like this: Lenses::AtCss.new('path').get(...)
    # that's a lot of ".new" that just becomes line noise
    # Classes don't seem to close over their environment as a function would (not sure why...)
    # so we can create anonymous classes with functions
    # Instead, we're just adding the helper functions to a simple hash.

    class << self
      def single
        Lens[
          get: :first.to_proc,
          put: lambda {|source, value| source[0] = value; source},
          create: lambda {|value| [value]}
        ]
      end

      def literal_to_string
        Lens[
          get: :to_s.to_proc,
          put: lambda do |source, value|
            if source.is_a?(RDF::Literal)
              RDF::Literal.new(value, language: source.language, datatype: source.datatype)
            else
              RDF::Literal.new(value)
            end
          end
        ]
      end

      def hash_update
        Lens[
          get: lambda {|hash| hash[key]},
          put: lambda {|hash, pair| hash.merge(pair[0] => pair[1])}
        ]
      end

      def orm_to_hash(name_to_lens)
        Lens[
          get: lambda do |orm|
            name_to_lens.reduce({}) do |hash, pair|
              key, lens = pair
              hash.merge(key => lens.get(orm))
            end
          end,
          put: lambda do |orm, hash|
            name_to_lens.each do |pair|
              key, lens = pair
              lens.put(orm, hash[key])
            end
            orm
          end
        ]
      end

      def as_dom
        Lens[
          # TODO figure out a memoizing strategy so we don't parse multiple times
          get: lambda {|xml| Nokogiri::XML(xml)},
          put: lambda {|xml, value| value.to_xml},
          create: lambda {|value| value.to_xml}
        ]
      end

      def at_css(selector)
        Lens[
          get: lambda {|doc| doc.at_css(selector).content},
          put: lambda {|doc, value| 
          doc.at_css(selector).content = value; doc},
          # can't do a css create because we don't know the structure
        ]
      end

      def get_predicate(predicate)
        Lens[
          get: lambda do |orm|
            orm.value(predicate)
          end,
          put: lambda do |orm, values|
            orm.graph.delete([orm.resource.subject_uri, predicate, nil])
            (values || []).each do |value|
              orm.graph.insert([orm.resource.subject_uri, predicate, value])
            end
            orm
          end,
          create: lambda do |values|
            orm = Ldp::Orm.new(Ldp::Resource.new(nil, '', RDF::Graph.new))
            values.each do |value|
              orm.graph.insert([orm.resource.subject_uri, predicate, value])
            end
            orm
          end
        ]
      end

      def load_model(klass)
        Lens[
          get: lambda do |id|
            klass.find(id)
          end,
          put: lambda do |id, model|
            model.save
            id
          end
        ]
      end

      def load_or_build_orm
        Lens[
          get: lambda do |uri|
            if uri.present?
              Ldp::Orm.new(Ldp::Resource.new(FedoraLens.connection, uri.to_s))
            else
              Ldp::Orm.new(Ldp::Resource.new(FedoraLens.connection, nil, RDF::Graph.new))
            end
          end,
          put: lambda do |uri, orm|
            if orm.resource.subject.present?
              orm.save
            else
              orm.resource.create
            end
            orm.resource.subject_uri
          end
        ]
      end

      def compose(outer, inner)
        Lens[
          get: lambda do |source|
            inner.get(outer.get(source))
          end,
          put: lambda do |source, value|
            outer.put(source, inner.put(outer.get(source), value))
          end
        ]
      end

      def zip(first, second)
      end
    end
  end
end
