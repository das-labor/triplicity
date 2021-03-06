#
# sync_action.rb - algorithm for copying new backups to secondary location and freeing up space
#
# Copyright (C) 2014 Thomas Stratmann <thomas.stratmann@rub.de>
# All rights reserved.
# This is free software with ABSOLUTELY NO WARRANTY.
#
# You can redistribute it and/or modify it under the terms of
# the GNU General Public License version 2.
#

require 'triplicity/util/sorting'

module Triplicity
  class SyncAction
    include Util::Sorting

    attr_reader :source_site, :target_site, :latest_target_timestamp

    def initialize(source_site, target_site, max_space = nil)
      @source_site, @target_site = source_site, target_site
      @latest_target_timestamp = target_site.latest_timestamp

      # mutating state:
      @remaining_space = max_space || Float::INFINITY
      # @old_target_chains is mutating as well
    end

    def perform
      remove_fitting_source_chains_from_old_target_chains

      fitting_source_chains.each do |chain|
        copy_chain_with_housekeeping(chain)
      end
    end

    private

    def remove_fitting_source_chains_from_old_target_chains
      fitting_source_chains.each do |chain|
        old_target_chains.delete_if { |tc| tc.base_timestamp == chain.base_timestamp }
      end
    end

    def old_target_chains
      # mutating value
      @old_target_chains ||= oldest_first(target_site.chains, :latest_timestamp)
    end

    def fitting_source_chains
      @fitting_source_chains ||= calculate_fitting_source_chains
    end

    def calculate_fitting_source_chains
      source_chains = youngest_first(source_site.chains, :latest_timestamp)

      remainder = @remaining_space
      source_chains.take_while do |chain|
        remainder -= chain.pessimistic_size
        remainder >= 0
      end
    end

    def copy_chain_with_housekeeping(chain)
      @remaining_space -= chain.pessimistic_size

      drop, keep = truncate_scenarios(old_target_chains).find do |drop_chains, keep_chains|
        keep_size = keep_chains.map(&:pessimistic_size).reduce(:+) || 0
        keep_size <= @remaining_space
      end

      drop.each(&:remove)
      old_target_chains.replace keep # bookkeeping

      chain.upload_to @target_site
      @latest_target_timestamp = [chain.latest_timestamp, @latest_target_timestamp].compact.max
    end

    def truncate_scenarios(chains)
      (0..chains.length).map { |i| [chains.take(i), chains.drop(i)] }
    end
  end
end
