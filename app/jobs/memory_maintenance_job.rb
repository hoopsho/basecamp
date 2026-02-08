# frozen_string_literal: true

class MemoryMaintenanceJob < ApplicationJob
  queue_as :default

  MAX_MEMORIES_PER_AGENT = 100
  BATCH_SIZE = 1000

  def perform
    Rails.logger.info "MemoryMaintenanceJob starting at #{Time.current}"

    pruned_count = 0
    summarized_count = 0

    Agent.find_each do |agent|
      agent_pruned = prune_expired_memories(agent)
      agent_summarized = summarize_old_memories(agent)

      pruned_count += agent_pruned
      summarized_count += agent_summarized
    end

    Rails.logger.info "MemoryMaintenanceJob completed: #{pruned_count} pruned, #{summarized_count} summarized"

    # Post summary to ops-log
    SlackService.post_message(
      channel: '#ops-log',
      text: ":brain: Memory maintenance complete: #{pruned_count} expired memories pruned, #{summarized_count} old memories summarized"
    )
  rescue StandardError => e
    Rails.logger.error "MemoryMaintenanceJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end

  private

  def prune_expired_memories(agent)
    expired = agent.agent_memories.expired.limit(BATCH_SIZE)
    count = expired.count

    if count > 0
      expired.destroy_all
      Rails.logger.info "Pruned #{count} expired memories for agent #{agent.name}"
    end

    count
  end

  def summarize_old_memories(agent)
    total_memories = agent.agent_memories.count

    return 0 if total_memories <= MAX_MEMORIES_PER_AGENT

    # Calculate how many to summarize
    to_summarize_count = total_memories - MAX_MEMORIES_PER_AGENT + 10 # Leave some buffer

    # Get old, low-importance memories
    old_memories = agent.agent_memories
                       .active
                       .where('importance < ?', 5)
                       .where('created_at < ?', 7.days.ago)
                       .order(importance: :asc, created_at: :asc)
                       .limit([ to_summarize_count, BATCH_SIZE ].min)

    return 0 if old_memories.empty?

    # Group by type and summarize
    grouped = old_memories.group_by(&:memory_type)

    summarized_count = 0

    grouped.each do |memory_type, memories|
      next if memories.size < 5 # Don't summarize unless we have enough

      # Create summary
      summary_content = create_summary(memories, memory_type)

      # Create new summary memory
      AgentMemory.create!(
        agent: agent,
        memory_type: :context,
        content: summary_content,
        importance: 6, # Higher importance so it doesn't get summarized again soon
        expires_at: 30.days.from_now
      )

      # Delete old memories
      memories.each(&:destroy)
      summarized_count += memories.size
    end

    Rails.logger.info "Summarized #{summarized_count} memories for agent #{agent.name}"

    summarized_count
  end

  def create_summary(memories, memory_type)
    time_range = "#{memories.first.created_at.strftime('%b %d')} - #{memories.last.created_at.strftime('%b %d')}"

    case memory_type
    when 'observation'
      "[Summary] #{memories.size} observations from #{time_range}: " +
        memories.last(3).map(&:content).join('; ')
    when 'working_note'
      "[Summary] #{memories.size} working notes from #{time_range}: " +
        "Key topics: #{extract_topics(memories)}"
    else
      "[Summary] #{memories.size} #{memory_type} memories from #{time_range}"
    end
  end

  def extract_topics(memories)
    # Simple topic extraction - in production could use LLM
    all_text = memories.map(&:content).join(' ').downcase

    # Extract common words (very basic implementation)
    words = all_text.scan(/\b[a-z]{4,}\b/)
    word_counts = words.group_by(&:itself).transform_values(&:count)

    # Get top 3 most common words
    word_counts.sort_by { |_, count| -count }.first(3).map(&:first).join(', ')
  end
end
