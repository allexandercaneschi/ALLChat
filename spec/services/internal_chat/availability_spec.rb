require 'rails_helper'

RSpec.describe InternalChat::Availability do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }

  def add_inbox(working_hours_enabled:)
    inbox = create(:inbox, account: account, working_hours_enabled: working_hours_enabled)
    create(:inbox_member, inbox: inbox, user: agent)
    inbox
  end

  it 'is never out of hours without an inbox with working hours' do
    add_inbox(working_hours_enabled: false)

    expect(described_class.out_of_hours?(agent, account)).to be(false)
  end

  it 'is out of hours when every inbox with working hours is closed' do
    inbox = add_inbox(working_hours_enabled: true)
    inbox.working_hours.each { |hour| hour.update!(closed_all_day: true, open_all_day: false) }

    expect(described_class.out_of_hours?(agent, account)).to be(true)
  end

  it 'is in hours when at least one inbox is open now' do
    closed = add_inbox(working_hours_enabled: true)
    closed.working_hours.each { |hour| hour.update!(closed_all_day: true, open_all_day: false) }
    open_inbox = add_inbox(working_hours_enabled: true)
    open_inbox.working_hours.each { |hour| hour.update!(closed_all_day: false, open_all_day: true) }

    expect(described_class.out_of_hours?(agent, account)).to be(false)
  end
end
