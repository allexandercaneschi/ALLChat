require 'rails_helper'

RSpec.describe AutoReply::ClassifyJob do
  it 'asks the guard to apply what Chip decides' do
    message = create(:message)
    guard = instance_double(AutoReply::Guard, apply_chip_verdict!: nil)
    allow(AutoReply::Guard).to receive(:new).with(message: message).and_return(guard)

    described_class.perform_now(message)

    expect(guard).to have_received(:apply_chip_verdict!)
  end
end
