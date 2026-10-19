require 'rails_helper'

RSpec.describe GoogleContacts::PhoneNumber do
  it 'maps Brazilian mobiles with and without the 9th digit to the same key' do
    with_nine = described_class.parse('+55 27 99876-5432')
    without_nine = described_class.parse('+552798765432')

    expect(with_nine.key).to eq(without_nine.key)
    expect(with_nine.chatwoot_format).to eq('+552798765432')
    expect(with_nine.google_format).to eq('+5527998765432')
  end

  it 'keeps landlines unchanged and adds the country code to local numbers' do
    number = described_class.parse('(27) 3222-1234')

    expect(number.chatwoot_format).to eq('+552732221234')
    expect(number.google_format).to eq('+552732221234')
  end

  it 'keeps international numbers as they are' do
    expect(described_class.parse('+1 415 555 1234').google_format).to eq('+14155551234')
  end

  it 'drops the trunk 0 and carrier code of old Brazilian formats' do
    ['(032) 99999-8888', '0xx32 99999-8888', '0 21 32 99999-8888', '+55 (032) 99999-8888'].each do |raw|
      expect(described_class.parse(raw).chatwoot_format).to eq('+553299998888')
    end
    expect(described_class.parse('032 3222-1234').chatwoot_format).to eq('+553232221234')
  end

  it 'never returns a number Chatwoot rejects as non E.164' do
    expect(described_class.parse('0800 123 4567')).to be_nil
    expect(described_class.parse('+0 123 456 789')).to be_nil
  end

  it 'returns nil for unreadable numbers' do
    expect(described_class.parse('123')).to be_nil
  end
end
