
#PQ-learning algorithm

#This line forces the correct output flow during execution
STDOUT.sync = true

#Problem 
load 'deep-sea-treasure.rb'

#Module for computing non-dominated sets and keeping the stamps
load 'non-dominated-stamp.rb'

#PARAMETERS
#####################################3
#Learning rate (by default; it can also be specified in the second argument)
Alpha = 0.1

#Exploration rate (by default; it can also be specified in the third argument)
Epsilon = 0.4

# Discount factor (by default; it can also be specified in the fourth argument)
Gamma=1

#Number of episodes (by default; it can also be specified in the fifth argument)
Episodes = 300001

# Flag for debugging
debugging = false

#Evaluation granularity (each Ev_Gran steps, different performances will be measured)
Ev_Gran = 1000

#Limit of steps for a single episode
Step_Limit = 1000

# Number of times that each learned policy will be exploited during the evaluation process
NSamples = 1

# Solution
Front = [[-1,1],[-3,2],[-5,3],[-7,5],[-8,8],[-9,16],[-13,24],[-14,50],[-17,74],[-19,124]]
#Front = [[-1,5]]

#Method for showing information if we are in debug mode
def log(string, debugging = false)
	if debugging
		puts string
	end
end

#For performing deep clones of objects
def deepcopy(x)
  Marshal.load(Marshal.dump(x))
end

def hv(front)
	sorted_front = front.sort { |a,b| a.v[0] <=> b.v[0]}

	x0 = -20
	y0 = 0
	hv = 0

	sorted_front.each do |value|
		hv += (value.v[0]-x0) * (value.v[1] - y0)
		x0 = value.v[0]
	end
	
	return hv
end

#Stamp generator
class StampGen
	def StampGen.reset
		@@last_stamp = -1
		@@last_final_stamp = 0
	end
	
	def StampGen.generateStamp
		@@last_stamp +=1
		return @@last_stamp
	end
	
end

# This class represents a possible result given a state and an action
class Result
  # p: probability
  # sp: resulting state after applying an action a to a state s
  # r: reward vector
  attr_accessor :p, :sp, :r
  
  def initialize(p,sp,r)
    @p,@sp,@r = p,sp,r
  end
  
  def to_s
    return "#{@p}, #{@sp.to_s}, #{@r}"
  end
end

#Class that represents a value object belonging to a Q(s,a) set
class Value
	
	#Vector value itself
	attr_accessor :v
	#s in Q(s,a)
	attr_accessor :s
	#a in Q(s,a)
	attr_accessor :a
	#Hash of values that have been used to update this value
	attr_accessor :stamping
	#Hash of values that have been updated by this value
	attr_accessor :stamped
	#Original value that originated this value. Used for propagating the stamping values to the values inside the Qs
	attr_accessor :original_value
	
	def initialize(v, s = nil, a = nil)
		@v = v
		@s = s
		@a = a
		@stamping = Hash.new(nil)
		@stamped = Hash.new(nil)
		@original_value = nil
	end
	
	def to_s
		#return "VALUE: #{@v}, STATE: #{@s}, ACTION: #{@a}\n      STAMPING:#{@stamping}\n       STAMPED:#{@stamped}"
		return "VALUE: #{@v}"
	end
	
	def == (other)
		return (self.v == other.v)
	end
	
	def eql(other)
		return (self.v == other.v)
	end
	
	def hash()
		return @v.hash
	end
	
	def clone()
		result = Value.new(@v, @s, @a)
		result.stamping = @stamping.clone
		result.stamped = @stamped.clone
		result.original_value = @original_value
		return result
	end
end


#Method that chooses the next greedy action to take if we are in state s.
#This selection is based on the table of values (q)
def greedy_action(q, s)
		
	#We fill an array with the actions that contribute to the ndu (repeated as many times they appear inside the ndu)
	#The more an action appears inside an ndu, the more chances to be chosen
	
	action_contributions = []
	NDU[s].values.each {|v|
		#if !action_contributions.include? v.a
			action_contributions << v.a
		#end
	}
	if !action_contributions.empty?
		return action_contributions[rand(action_contributions.size)]
	else
		return Actions[rand(Actions.size)]
	end
end


##############   MAIN    #################

run_number = 0
alpha = Alpha
epsilon = Epsilon
gamma = Gamma
episodes = Episodes
#Read arguments
#The first argument is the run number
if ARGV.length > 0
	run_number = ARGV.first
	#Then alpha, epsilon, gamma and episodes
	if ARGV.length > 1
		alpha = ARGV[1]
		epsilon = ARGV[2]
		gamma = ARGV[3]
		episodes = ARGV[4]
	end
end

#Create directories where the information of the experiment will be stored
runDirName = "#{File.dirname(__FILE__)}/Run#{run_number}"
Dir.mkdir(runDirName) unless File.exists?(runDirName)
#t = Time.now
#dirName = "#{File.dirname(__FILE__)}/Run#{run_number}/Experiment-#{t.day}-#{t.month}-at-#{t.hour}-#{t.min}"
#Dir.mkdir(dirName)

#Initial state
h = initial_state()

#Reset the stamp generator
StampGen.reset

# Create all possible states
States = create_states()

# Define results for each state (in a hash of hashes)
Results = {}
for s in States
  Results[s] ||= {}
  for a in Actions
    Results[s][a] = transition(s,a)
  end
end

# Definition of some necessary structures
#Non-Dominated sets of values of a state (Hash structure. key: state; value: object of the class NonDominated, defined in module non-dominated-stamp.rb)
NDU = {}
#Non-Dominated sets of values of a state-action pair (Hash structure. key: [state, action]; value: object of the class NonDominated, defined in module non-dominated-stamp.rb)
Q = {}
#Hash structure. key: [state, action]; value: hash structure containing the stamps that have stamped s,a from another state sp
Stamps = {}
#Hash structure. key: integer; value: state object corresponding to the state whose NDU contains the stamping value associated to the stamp in the key
StateOfStamp = {}
#For learning transition probabilities (these are not using during learning, is just for learning the model). Is a hash of hashes
P = {}

#Initialization of the previously defined structutes
for s in States
  NDU[s] = NonDominated.new([])
  for a in Actions  
    Q[[s,a]] = NonDominated.new([])
    Stamps[[s,a]] = {}
    P[[s,a]] = {}
    for s1 in States
	 P[[s,a]][s1] = 0   
    end
  end	  
end

#counter for non-stationary policies during evaluation
non_stationary = 0

##############   MAIN    #################

puts "INFO [#{Time.now}]: Running Pareto Q-learning"

#Initialize episode number
episode = 0

#Initialize time step number
global_time_step = 0

#Array that stores the reached values during the learning process
online_values = []

puts "INFO [#{Time.now}]: Learning..."

#Number of steps required to obtain the complete NDU[h]
steps_required = nil
episodes_required = nil

# The learning process begins now
t1 = Time.now

# write hypervolumes
File.open("#{runDirName}/hv_learned.csv", 'w') do |f|
	f.write("actions,hypervolume\n")

while episode < episodes
	  
  #Set initial state
  s = h
   
  #Episode just began
  ended = false
  n_steps = 0
  
  #Init accumulated discounted reward
  acc_disc_reward = Array.new(RSize,0)

  while !ended
	
	n_steps = n_steps + 1
	
	# Choose action to update, according to an e-greedy exploration policy
	if rand() <= epsilon
		#We choose an unique, totally random action and a random associated id
		updated_action = Actions[rand(Actions.size)]
	else
		#We choose an unique action based on a greedy policy
		updated_action = greedy_action(Q, s)
	end
	
	#We obtain the stochastic result of executing the selected action
	results = Results[s][updated_action]
	if results.size == 1
		result = results.first
	else
		if rand < results.first.p
			result= results[0]
		else
			result = results[1]
		end
	end
	
	#Update the reward
	for j in 0..(RSize-1)
		acc_disc_reward[j] += (gamma**(n_steps-1))*result.r[j]
	end
	
	#Reached state
	sp = result.sp
	
	#If the hash for the stamps that have updated some value of the Q-set of the pair [s, updated_action] is not initialized yet, we do it now
	if Stamps[[s,updated_action]][result.sp] == nil
		Stamps[[s,updated_action]][result.sp]  = []
	end
	
	log("Obtained reward: #{result.r}", debugging)
	
	if is_final_state?(result.r, result.sp) #If we are at a final state
		
		log("INFO [#{Time.now}], [Episode #{episode}]: FINAL STATE WITH REWARD #{result.r} in #{n_steps} steps!!! -------------------------------------------------------------------", debugging)
		ended = true #End of the episode
		
		#We update the Q-value
		log( "Before update...", debugging)
		log( "Q[[#{s},#{updated_action}]]; #{Q[[s, updated_action]].to_s}", debugging)
		
		Q[[s,updated_action]] = Q[[s, updated_action]].update(result.r, s, updated_action, sp, alpha)
		
		log( "After update r...", debugging)
		log( "Q[[#{s},#{updated_action}]]; #{Q[[s,updated_action]].to_s}", debugging)
		
	else
		#We compute the non-dominated set corresponding to the reached state sp
		values = []
		Actions.each do |a|
			values += Q[[result.sp,a]].values.to_a
		end
		NDU[result.sp] = NonDominated.new(values.uniq)
				
		#We update the Q-value
		log( "Before update...", debugging)
		log( "Q[[#{s},#{updated_action}]]; #{Q[[s, updated_action]].to_s}", debugging)
		log( "NDU[#{result.sp}]; #{NDU[result.sp].to_s}", debugging)
		
		Q[[s,updated_action]] = Q[[s, updated_action]].update((NDU[result.sp]*gamma).sum(result.r), s, updated_action, result.sp, alpha, result.r)
		
		log( "After update...", debugging)
		log( "Q[[#{s},#{updated_action}]]; #{Q[[s,updated_action]].to_s}", debugging)
		
	end
	
	#Next state
	s = result.sp
	
	#If we reach the limit of steps for a single episode, we end it
	if n_steps == Step_Limit
		ended = true
	end
	
	global_time_step += 1
	
	values = []
	Actions.each do |a|
		values += Q[[h,a]].values.to_a
	end
	NDU[h] = NonDominated.new(values.uniq)
	
	if steps_required == nil
		ok = true
		s_index = 0
		while (ok and s_index < Front.size) do
			found = false
			ts_index = 0
			while (!found and ts_index < NDU[h].values.size) do
				if NDU[h].dominant(Value.new(Front[s_index]), NDU[h].values[ts_index]) == 0
					found = true
				end
				ts_index += 1
			end
			if !found 
				ok = false
			end
			s_index += 1
		end
		if ok
			episodes_required = episode + 1
			steps_required = global_time_step
		end
	end
	
	#If the current time step is a multiple of the evaluation granularity, we carry out some performance measures
	if ((global_time_step % Ev_Gran) == 0)
		#First performance measure: NDU of the initial state
		#-----------------------------------------------------------------------------------------------------------------------------------
		puts "INFO [#{Time.now}], [Time step #{global_time_step}]: Writing NDU[h]..."
		
		hv_v0 = hv(NDU[h].values)
		f.write("#{global_time_step}, #{hv_v0}\n")
		puts NDU[h]
		
		if false 
		#puts "INFO [#{Time.now}], [Time step #{global_time_step}]: NDU[home]:"
		#puts NDU[h]
		
		#Second performance measure: Online performance (rewards obtained 
		#-----------------------------------------------------------------------------------------------------------------------------------
		#puts "INFO [#{Time.now}], [Time step #{global_time_step}]: Measuring online performance..."
		
		#As several different rewards, non comparable between them, are obtained along the learning process, we store it into an array of unique values
		#and then we will compute the hypervolume of this set of rewards. The more the hypervolume increases, the better the online performance is
		
		online_values << acc_disc_reward
		online_values = online_values.uniq
		
		File.open("#{runDirName}/online_values-#{global_time_step}.txt", 'w') do |f|

			for value in online_values
				value.each_with_index {|v_component, i|
					if i == 0
						#We multiply by -1 for computing the hypervolume later with the python script
						f.write(v_component*-1)
					else
						f.write(", #{v_component*-1}")
					end
				}
				f.write("\n")
			end
			
		end
		
		#puts "INFO [#{Time.now}], [Time step #{global_time_step}]: Online performance measured"
		
		#Third performance measure: exploiting the different learned policies so far
		#-----------------------------------------------------------------------------------------------------------------------------------
		#puts "INFO [#{Time.now}], [Time step #{global_time_step}]: Exploiting the policies..."
		
		#Updating NDUs...
		States.each do |estadito|
			values = []
			Actions.each do |a|
				values += Q[[estadito,a]].values.to_a
			end
			NDU[estadito] = NonDominated.new(values.uniq)
		end
		
		#Here we will store the different rewards obtained by each policy (on average, for each policy)
		sampling_values = []
		#We exploit every learned policy
		p = 0
		while p < NDU[h].values.size
			
			policy_ok = true
			states_visited = [h]
		
			avg_acc_disc_reward = Array.new(RSize,0)
			NSamples.times do
				
				#0. Initialization
				acc_disc_reward = Array.new(RSize,0)
				step = 0
				#1. Take the corresponding policy value inside NDU[h]
				policy_value = NDU[h].values[p]
				action = policy_value.a
				#2. Take the action
				#We obtain the stochastic result of executing the selected action
				results = Results[h][action]
				if results.size == 1
					result = results.first
				else
					if rand < results.first.p
						result= results[0]
					else
						result = results[1]
					end
				end
				#3.Sum the reward
				for j in 0..(RSize-1)
					acc_disc_reward[j] += (gamma**step)*result.r[j]
				end
				
				#4.Next state
				current_state = result.sp
				
				while (!is_final_state?(result.r, result.sp) && (step <= 1000)) do
					
					step += 1
					#1. Search inside the NDU of the current state for the value that has stamped the previous value
									
					found = false
					i = 0
					while (!found and (i < NDU[current_state].values.size))
						
						if policy_value.stamped[current_state] == NDU[current_state].values[i].stamping[[policy_value.s, policy_value.a]]
							found = true
							policy_value = NDU[current_state].values[i]
						end
						
						i += 1
					end
					if found
						action = policy_value.a
					else NDU[current_state].values.size > 0
						policy_value = NDU[current_state].values[rand(NDU[current_state].values.size)]
						action = policy_value.a
						policy_ok = false
					end
					#2. Take the action
					#We obtain the stochastic result of executing the selected action
					results = Results[current_state][action]
					if results.size == 1
						result = results.first
					else
						if rand < results.first.p
							result= results[0]
						else
							result = results[1]
						end
					end
					
					#3.Sum the reward
					for j in 0..(RSize-1)
						acc_disc_reward[j] += (gamma**step)*result.r[j]
					end
					#4.Next state
					current_state = result.sp
					#Check for non-stationary policies (only if the followed policy is complete)
					if policy_ok
						if states_visited.include? current_state
							non_stationary += 1
						else
							states_visited << current_state
						end
					end
					
				end
				
				for j in 0..(RSize-1)
					avg_acc_disc_reward[j] += acc_disc_reward[j]
				end
			end
			
			#Store average reward for this policy
			for j in 0..(RSize-1)
				avg_acc_disc_reward[j] = avg_acc_disc_reward[j].quo(NSamples)
			end
			sampling_values << Value.new(avg_acc_disc_reward)
			
			#Next policy
			p+=1
		end
		
		sampling_set = NonDominated.new(sampling_values)
		
		#puts "INFO [#{Time.now}], [Time step #{global_time_step}]: Policies exploited"
		
		File.open("#{runDirName}/sampling_values-#{global_time_step}.txt", 'w') do |f|

			for value in sampling_set.values
				f.write("#{value.v[0]*-1}, #{value.v[1]*-1}\n")
			end
			
		end
		
		end
	end
end

 episode += 1
  
end


end

if false
# When the episodes are done, we compute again the NDUs for taking into account the lastly updated Q-sets
puts "INFO [#{Time.now}], [Episode #{episode}]: Computing NDUs"
States.each do |s|
	values = []
	Actions.each do |a|
		values += Q[[s,a]].values.to_a
	end
	NDU[s] = NonDominated.new(values.uniq)
end
values = []
Actions.each do |a|
	values += Q[[h,a]].values.to_a
end
NDU[h] = NonDominated.new(values.uniq)
puts "INFO [#{Time.now}], [Episode #{episode}]: NDU[home]:"
puts NDU[h]
end

#The learning process ends now
t2 = Time.now

puts "INFO [#{Time.now}]: MO Q-learning done"
puts "INFO [#{Time.now}]: Elapsed time: #{t2 - t1} seconds"

# Store results
#puts "INFO [#{Time.now}]: Writing results in files"

t = t2

#for s in States
#	write_ndu(dirName, s, NDU[s])
#	Actions.each do |a|
#		write_q(dirName, s, a, Q[[s,a]])
#	end
#end

write_readme(runDirName, NDU[h].c, alpha, gamma, epsilon, t2-t1, episodes, non_stationary, steps_required, episodes_required)

#puts "INFO [#{Time.now}]: Results written"


