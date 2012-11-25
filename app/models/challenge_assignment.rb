class ChallengeAssignment < ActiveRecord::Base
  # We use "-1" to represent all the requested items matching
  ALL = -1

  belongs_to :collection
  belongs_to :offer_signup, :class_name => "ChallengeSignup"
  belongs_to :request_signup, :class_name => "ChallengeSignup"
  belongs_to :pinch_hitter, :class_name => "Pseud"
  belongs_to :pinch_request_signup, :class_name => "ChallengeSignup"
  belongs_to :creation, :polymorphic => true

  scope :for_request_signup, lambda {|signup| where('request_signup_id = ?', signup.id)}

  scope :for_offer_signup, lambda {|signup| where('offer_signup_id = ?', signup.id)}

  scope :in_collection, lambda {|collection| where('challenge_assignments.collection_id = ?', collection.id) }

  scope :defaulted, where("defaulted_at IS NOT NULL")
  scope :undefaulted, where("defaulted_at IS NULL")
  scope :uncovered, where("covered_at IS NULL")
  scope :covered, where("covered_at IS NOT NULL")
  scope :sent, where("sent_at IS NOT NULL")
  
  scope :with_pinch_hitter, where("pinch_hitter_id IS NOT NULL")

  scope :with_offer, where("offer_signup_id IS NOT NULL")
  scope :with_request, where("request_signup_id IS NOT NULL")
  scope :with_no_request, where("request_signup_id IS NULL")
  scope :with_no_offer, where("offer_signup_id IS NULL")

  # sorting by request/offer
  
  REQUESTING_PSEUD_JOIN = "INNER JOIN challenge_signups ON (challenge_assignments.request_signup_id = challenge_signups.id
                                                            OR challenge_assignments.pinch_request_signup_id = challenge_signups.id)
                           INNER JOIN pseuds ON challenge_signups.pseud_id = pseuds.id"

  OFFERING_PSEUD_JOIN = "LEFT JOIN challenge_signups ON challenge_assignments.offer_signup_id = challenge_signups.id
                         INNER JOIN pseuds ON (challenge_assignments.pinch_hitter_id = pseuds.id OR challenge_signups.pseud_id = pseuds.id)"

  scope :order_by_requesting_pseud, joins(REQUESTING_PSEUD_JOIN).order("pseuds.name")

  scope :order_by_offering_pseud, joins(OFFERING_PSEUD_JOIN).order("pseuds.name")


  # Get all of a user's assignments 
  scope :by_offering_user, lambda {|user|
    select("DISTINCT challenge_assignments.*").
    joins(OFFERING_PSEUD_JOIN).
    joins("INNER JOIN users ON pseuds.user_id = users.id").
    where('users.id = ?', user.id)
  }

  # sorting by fulfilled/posted status
  COLLECTION_ITEMS_JOIN = "INNER JOIN collection_items ON (collection_items.collection_id = challenge_assignments.collection_id AND
                                                           collection_items.item_id = challenge_assignments.creation_id AND
                                                           collection_items.item_type = challenge_assignments.creation_type)"

  COLLECTION_ITEMS_LEFT_JOIN =  "LEFT JOIN collection_items ON (collection_items.collection_id = challenge_assignments.collection_id AND
                                                                collection_items.item_id = challenge_assignments.creation_id AND
                                                                collection_items.item_type = challenge_assignments.creation_type)"
                                                                
  WORKS_JOIN = "INNER JOIN works ON works.id = challenge_assignments.creation_id AND challenge_assignments.creation_type = 'Work'"
  WORKS_LEFT_JOIN = "LEFT JOIN works ON works.id = challenge_assignments.creation_id AND challenge_assignments.creation_type = 'Work'"
  
  scope :fulfilled,
    joins(COLLECTION_ITEMS_JOIN).joins(WORKS_JOIN).
    where('challenge_assignments.creation_id IS NOT NULL AND collection_items.user_approval_status = ? AND collection_items.collection_approval_status = ? AND works.posted = 1',
                    CollectionItem::APPROVED, CollectionItem::APPROVED)


  scope :posted, joins(WORKS_JOIN).where("challenge_assignments.creation_id IS NOT NULL AND works.posted = 1")

  # should be faster than unfulfilled scope because no giant left joins
  def self.unfulfilled_in_collection(collection)
    fulfilled_ids = ChallengeAssignment.in_collection(collection).fulfilled.value_of(:id)
    fulfilled_ids.empty? ? in_collection(collection) : in_collection(collection).where("challenge_assignments.id NOT IN (?)", fulfilled_ids)
  end
  
  # faster than unposted scope because no left join!
  def self.unposted_in_collection(collection)
    posted_ids = ChallengeAssignment.in_collection(collection).posted.value_of(:id)
    posted_ids.empty? ? in_collection(collection) : in_collection(collection).where("'challenge_assignments.creation_id IS NULL OR challenge_assignments.id NOT IN (?)", posted_ids)
  end    
    
  # has to be a left join to get assignments that don't have a collection item
  scope :unfulfilled,
    joins(COLLECTION_ITEMS_LEFT_JOIN).joins(WORKS_LEFT_JOIN).
    where('challenge_assignments.creation_id IS NULL OR collection_items.user_approval_status != ? OR collection_items.collection_approval_status != ? OR works.posted = 0', CollectionItem::APPROVED, CollectionItem::APPROVED)

  # ditto
  scope :unposted, joins(WORKS_LEFT_JOIN).where("challenge_assignments.creation_id IS NULL OR works.posted = 0")

  scope :unstarted, where("challenge_assignments.creation_id IS NULL")


  before_destroy :clear_assignment
  def clear_assignment
    if offer_signup
      offer_signup.assigned_as_offer = false
      offer_signup.save
    end

    if request_signup
      request_signup.assigned_as_request = false
      request_signup.save
    end
  end
  
  def request
    self.request_signup || self.pinch_request_signup
  end

  def get_collection_item
    return nil unless self.creation
    CollectionItem.where("collection_id = ? AND item_id = ? AND item_type = ?", self.collection_id, self.creation_id, self.creation_type).first
  end

  def fulfilled?
    self.posted? && (item = get_collection_item) && item.approved?
  end
  
  def posted?
    self.creation && (creation.respond_to?(:posted?) ? creation.posted? : true)
  end

  def defaulted=(value)
    if value == "1"
      self.defaulted_at = Time.now
    else
      self.defaulted_at = nil
    end
  end

  def defaulted
    !self.defaulted_at.nil?
  end
  
  include Comparable
  # sort in order that puts assignments with no request ahead of assignments with no offer,
  # ahead of assignments with both request and offer, and within each group sorts by
  # request byline and then offer byline.
  def <=>(other)
    return -1 if self.request_signup.nil? && other.request_signup
    return 1 if other.request_signup.nil? && self.request_signup
    return -1 if self.offer_signup.nil? && other.offer_signup
    return 1 if other.offer_signup.nil? && self.offer_signup
    cmp = self.request_byline.downcase <=> other.request_byline.downcase
    return cmp if cmp != 0
    self.offer_byline.downcase <=> other.offer_byline.downcase
  end

  def title
    "#{self.collection.title} (#{self.request_byline})"
  end

  def offering_user
    offering_pseud ? offering_pseud.user : nil
  end

  def offering_pseud
    offer_signup ? offer_signup.pseud : pinch_hitter
  end

  def requesting_pseud
    request_signup ? request_signup.pseud : (pinch_request_signup ? pinch_request_signup.pseud : nil)
  end

  def offer_byline
    offer_signup && offer_signup.pseud ? offer_signup.pseud.byline : (pinch_hitter ? (pinch_hitter.byline + "* (pinch hitter)") : "- none -")
  end

  def request_byline
    request_signup && request_signup.pseud ? request_signup.pseud.byline : (pinch_request_signup ? (pinch_request_byline + "* (pinch recipient)") : "- None -")
  end

  def pinch_hitter_byline
    pinch_hitter ? pinch_hitter.byline : ""
  end

  def pinch_hitter_byline=(byline)
    self.pinch_hitter = Pseud.by_byline(byline).first
  end

  def pinch_request_byline
    pinch_request_signup ? pinch_request_signup.pseud.byline : ""
  end

  def pinch_request_byline=(byline)
    pinch_pseud = Pseud.by_byline(byline).first
    self.pinch_request_signup = ChallengeSignup.in_collection(self.collection).by_pseud(pinch_pseud).first if pinch_pseud
  end
  
  def default
    self.defaulted_at = Time.now
    save
  end

  def cover(pseud)
    new_assignment = self.covered_at ? request.request_assignments.last : ChallengeAssignment.new
    new_assignment.collection = self.collection
    new_assignment.request_signup_id = request.id
    new_assignment.pinch_hitter = pseud
    new_assignment.sent_at = nil
    new_assignment.save!
    new_assignment.send_out
    self.covered_at = Time.now
    new_assignment.save && save
  end

  def send_out
    # don't resend!
    unless self.sent_at
      self.sent_at = Time.now
      save
      assigned_to = self.offer_signup ? self.offer_signup.pseud.user : (self.pinch_hitter ? self.pinch_hitter.user : nil)
      request = self.request_signup || self.pinch_request_signup
      UserMailer.challenge_assignment_notification(collection.id, assigned_to.id, self.id).deliver if assigned_to && request
    end
  end

  @queue = :collection
  # This will be called by a worker when a job needs to be processed
  def self.perform(method, *args)
    self.send(method, *args)
  end

  # send assignments out to all participants
  def self.send_out(collection)
    Resque.enqueue(ChallengeAssignment, :delayed_send_out, collection.id)
  end

  def self.delayed_send_out(collection_id)
    collection = Collection.find(collection_id)

    # update the collection challenge with the time the assignments are sent
    challenge = collection.challenge
    challenge.assignments_sent_at = Time.now
    challenge.save

    # send out each assignment
    collection.assignments.each do |assignment|
      assignment.send_out
    end
    collection.notify_maintainers("Assignments Sent", "All assignments have now been sent out.")

    # purge the potential matches! we don't want bazillions of them in our db
    PotentialMatch.clear!(collection)
  end

  # generate automatic match for a collection
  # this requires potential matches to already be generated
  def self.generate(collection)
    Resque.enqueue(ChallengeAssignment, :delayed_generate, collection.id)
  end

  def self.delayed_generate(collection_id)
    collection = Collection.find(collection_id)
    settings = collection.challenge.potential_match_settings

    ChallengeAssignment.clear!(collection)

    # we sort signups into buckets based on how many potential matches they have
    @request_match_buckets = {}
    @offer_match_buckets = {}
    @max_match_count = 0
    if settings.nil? || settings.no_match_required?
       # stuff everyone into the same bucket
       @max_match_count = 1
       @request_match_buckets[1] = collection.signups
       @offer_match_buckets[1] = collection.signups
    else    
      collection.signups.find_each do |signup|
        next if signup.nil?
        request_match_count = signup.request_potential_matches.count
        @request_match_buckets[request_match_count] ||= []
        @request_match_buckets[request_match_count] << signup
        @max_match_count = (request_match_count > @max_match_count ? request_match_count : @max_match_count)

        offer_match_count = signup.offer_potential_matches.count
        @offer_match_buckets[offer_match_count] ||= []
        @offer_match_buckets[offer_match_count] << signup
        @max_match_count = (offer_match_count > @max_match_count ? offer_match_count : @max_match_count)
      end
    end

    # now that we have the buckets, we go through assigning people in order
    # of people with the fewest options first.
    # if someone has no potential matches they still get an assignment, just with no
    # match.
    0.upto(@max_match_count) do |count|
      if @request_match_buckets[count]
        @request_match_buckets[count].sort_by {rand}.each do |request_signup|
          # go through the potential matches in order from best to worst and try and assign
          request_signup.reload
          next if request_signup.assigned_as_request
          ChallengeAssignment.assign_request!(collection, request_signup)
        end
      end

      if @offer_match_buckets[count]
        @offer_match_buckets[count].sort_by {rand}.each do |offer_signup|
          offer_signup.reload
          next if offer_signup.assigned_as_offer
          ChallengeAssignment.assign_offer!(collection, offer_signup)
        end
      end
    end
    UserMailer.potential_match_generation_notification(collection.id).deliver
  end

  # go through the request's potential matches in order from best to worst and try and assign
  def self.assign_request!(collection, request_signup)
    assignment = ChallengeAssignment.new(:collection => collection, :request_signup => request_signup)
    last_choice = nil
    assigned = false
    request_signup.request_potential_matches.sort.reverse.each do |potential_match|
      # skip if this signup has already been assigned as an offer
      next if potential_match.offer_signup.assigned_as_offer

      # if there's a circular match let's save it as our last choice
      if potential_match.offer_signup.assigned_as_request && !last_choice &&
          collection.assignments.for_request_signup(potential_match.offer_signup).first.offer_signup == request_signup
        last_choice = potential_match
        next
      end

      # otherwise let's use it
      assigned = ChallengeAssignment.do_assign_request!(assignment, potential_match)
      break
    end

    if !assigned && last_choice
      ChallengeAssignment.do_assign_request!(assignment, last_choice)
    end

    request_signup.assigned_as_request = true
    request_signup.save!

    assignment.save!
    assignment
  end

  # go through the offer's potential matches in order from best to worst and try and assign
  def self.assign_offer!(collection, offer_signup)
    assignment = ChallengeAssignment.new(:collection => collection, :offer_signup => offer_signup)
    last_choice = nil
    assigned = false
    offer_signup.offer_potential_matches.sort.reverse.each do |potential_match|
      # skip if already assigned as a request
      next if potential_match.request_signup.assigned_as_request

      # if there's a circular match let's save it as our last choice
      if potential_match.request_signup.assigned_as_offer && !last_choice &&
          collection.assignments.for_offer_signup(potential_match.request_signup).first.request_signup == offer_signup
        last_choice = potential_match
        next
      end

      # otherwise let's use it
      assigned = ChallengeAssignment.do_assign_offer!(assignment, potential_match)
      break
    end

    if !assigned && last_choice
      ChallengeAssignment.do_assign_offer!(assignment, last_choice)
    end

    offer_signup.assigned_as_offer = true
    offer_signup.save!

    assignment.save!
    assignment
  end

  def self.do_assign_request!(assignment, potential_match)
    assignment.offer_signup = potential_match.offer_signup
    potential_match.offer_signup.assigned_as_offer = true
    potential_match.offer_signup.save!
  end

  def self.do_assign_offer!(assignment, potential_match)
    assignment.request_signup = potential_match.request_signup
    potential_match.request_signup.assigned_as_request = true
    potential_match.request_signup.save!
  end

  # clear out all previous assignments.
  # note: this does NOT invoke callbacks because ChallengeAssignments don't have any dependent=>destroy
  # or associations
  def self.clear!(collection)
    ChallengeAssignment.delete_all(:collection_id => collection.id)
    ChallengeSignup.update_all({:assigned_as_offer => false, :assigned_as_request => false}, {:collection_id => collection.id})
  end

  # create placeholders for any assignments left empty
  # (this is for after manual updates have left some users without an
  # assignment)
  def self.update_placeholder_assignments!(collection)
    collection.signups.each do |signup|
      if signup.request_assignments.count > 1
        # get rid of empty placeholders no longer needed
        signup.request_assignments.each do |assignment|
          assignment.destroy if assignment.offer_signup.blank?
        end
      end
      if signup.request_assignments.empty?
        # not assigned to giver anymore! :(
        assignment = ChallengeAssignment.new(:collection => collection, :request_signup => signup)
        assignment.save
      end
      if signup.offer_assignments.count > 1
        signup.offer_assignments.each do |assignment|
          assignment.destroy if assignment.request_signup.blank?
        end
      end
      if signup.offer_assignments.empty?
        assignment = ChallengeAssignment.new(:collection => collection, :offer_signup => signup)
        assignment.save
      end
    end
  end

end
