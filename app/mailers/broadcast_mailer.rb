# ALLChat: e-mail copy of a broadcast, sent from the installation sender (MAILER_SENDER_EMAIL).
class BroadcastMailer < ApplicationMailer
  def broadcast
    mail(to: params[:email], subject: params[:subject]) do |format|
      format.text { render plain: params[:content] }
    end
  end
end
