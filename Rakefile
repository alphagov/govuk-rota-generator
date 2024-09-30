require_relative "bin/sync_pagerduty.rb"

desc "Send publishable item links of a specific type to Publishing API (ie, 'CaseStudy')."
task :sync_pagerduty, [:bulk_apply_overrides] do |_, args|
  SyncPagerduty.new.execute(bulk_apply_overrides: args[:bulk_apply_overrides] == "true")
end
