# encoding: UTF-8
class Reservation < ActiveRecord::Base
  extend Forwardable
  delegate [:gocardless_url, :paypal_partial, :formatted_price, :resource_category] => :ticket_type

  belongs_to :ticket_type
  has_many :waiting_list_entries, dependent: :destroy
  has_many :gocardless_bills

  PAYMENT_METHODS = %w{paypal gocardless cheque}
  validates_presence_of :name, :email, :phone_number, :what_can_you_help_with
  validates_email_format_of :email
  validates :payment_method, inclusion: {in: PAYMENT_METHODS}
  validates_presence_of :ticket_type

  state_machine :state, :initial => :new do
    state :new
    state :reserved
    state :waiting_list
    state :paid do
      transition to: :payment_cleared, on: :payment_cleared
    end
    state :payment_cleared
    state :cancelled
    state :payment_on_arrival

    event :reserve do
      transition [:new, :waiting_list] => :reserved
    end

    event :cancel do
      transition [:new, :reserved, :waiting_list] => :cancelled
    end

    after_transition any => :cancelled, :do => :remove_from_waiting_list
  end

  def self.reserved
    where(state: [:reserved, :paid, :payment_cleared, :payment_on_arrival])
  end

  def self.cancelled
    where(state: :cancelled)
  end

  def remove_from_waiting_list
    waiting_list_entries.destroy_all
  end
  
  def add_to_waiting_list(waiting_list_resource_category)
    connection.transaction do
      self.state = "waiting_list" if waiting_list_resource_category == self.resource_category
      waiting_list_entries.create(resource_category: waiting_list_resource_category, added_at: requested_at)
      save!
    end
  end

  def self.waiting_for(resource_category)
    joins(:waiting_list_entries).where("waiting_list_entries.resource_category" => resource_category)
  end

  def self.in_resource_category(resource_category)
    joins(:ticket_type).where("ticket_types.resource_category" => resource_category)
  end

  def reserve(clock = DateTime)
    super
    set_payment_due!(clock)
  end

  def set_payment_due!(clock = DateTime)
    self.payment_due = clock.now + if payment_method == 'cheque'
      2.weeks
    else
      1.week
    end
    save
  end

  def total_paid_in_pence
    gocardless_bills.sum(&:amount_in_pence)
  end

  def balance
    ticket_type && (ticket_type.price_in_pence - total_paid_in_pence)
  end
end