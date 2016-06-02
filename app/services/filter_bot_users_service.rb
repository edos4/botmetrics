class FilterBotUsersService
  def initialize(bot, query_set, time_zone)
    @bot       = bot
    @query_set = query_set
    @time_zone = time_zone
  end

  def scope
    collection = BotUser.where(bot_instance_id: legit_bot_instances.ids)

    query_set.queries.each do |query|
      next if query.value.blank? && (query.min_value.blank? || query.max_value.blank?)

      collection = chain_to(collection, query)
    end
    collection
  end

  private

    attr_reader :bot, :query_set, :time_zone

    def legit_bot_instances
      bot.instances.legit
    end

    def chain_to(collection, query)
      case
        when query.is_string_query?
          chain_with_string_query(collection, query)
        when query.is_number_query?
          chain_with_number_query(collection, query)
        when query.is_datetime_query?
          chain_with_datetime_query(collection, query)
        else
          collection
      end
    end

    def chain_with_string_query(collection, query)
      case
        when query.method == 'equals_to'
          collection.where(
            [
              "bot_users.user_attributes->>:field = :value",
              field: query.field,
              value: query.value
            ]
          )
        when query.method == 'contains'
          collection.where(
            [
              "bot_users.user_attributes->>:field ilike :value",
              field: query.field,
              value: "%#{query.value}%"
            ]
          )
      end
    end

    def chain_with_number_query(collection, query)
      case
        when query.field == 'interaction_count'
          collection =
            collection.
              joins(:events).
              where(events: { event_type: 'message', bot_instance: bot.instances.legit, is_for_bot: true }).
              group('bot_users.id')

          if query.method == 'equals_to'
            collection.having('count(*) = ?', query.value)
          else
            collection.having('count(*) BETWEEN ? AND ?', query.min_value, query.max_value)
          end
      end
    end

    def chain_with_datetime_query(collection, query)
      case
        when query.field == 'interacted_at'
          collection.
            joins(:events).
            where(events: { event_type: 'message', bot_instance: bot.instances.legit, is_for_bot: true }).
            where('events.created_at BETWEEN ? AND ?', query.min_value.in_time_zone(time_zone), query.max_value.in_time_zone(time_zone)).
            uniq
      end
    end
end