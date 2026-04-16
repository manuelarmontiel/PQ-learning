#Module for computing non-dominated sets and keeping the stamps
load 'non-dominated-stamp.rb'

# Prepare Deep Sea Treasure  environment
FIXNUM_MIN = 0

# Size of the grid
Rows = 11
Columns = 10

# Size of the reward vector 
RSize=2

# Possible actions
Actions=[:left,:right,:up,:down]
#Actions=[:right,:down]

#Probability of noise
PNoise = 0

#Probability of pirates
PPirate = 0

# Position of home (Column, Row)
H = [0,10]

# Positions of treasures
T = [[0,9], [1,8], [2,7], [3,6], [4,6], [5,6], [6,3], [7,3], [8,1], [9,0]]

# Rewards of treasures
R = [1, 2, 3, 5, 8, 16, 24, 50, 74, 124]

#Position of sea floor
SF = [[5,5],[5,4]]

class State
  # x, y: the position
  attr_accessor :x, :y
  
  def initialize(x,y)
    @x,@y = x,y
  end
  
  def [](*r)
    return to_a()[*r]
  end
  
  def to_a()
    [@x,@y]
  end
  
  def ==(other)
    to_a() == other.to_a()
  end
  
  def eql?(other)
    self==other
  end
  
  def hash()
    to_a().hash()
  end
  
  def up()
    State.new(@x,[Rows-1,@y+1].min)
  end
  
  def down()
    State.new(@x,[0,@y-1].max)
  end
  
  def left()
    s = State.new([0,@x-1].max,@y)
    loc = [s.x, s.y]
    if SF.include? loc
	    s = State.new(@x, @y)
    end
    return s
  end
  
  def right()
    State.new([Columns-1,@x+1].min,@y)
  end
  
  def rest()
    State.new(*to_a)
  end
  
  def adjacent?(s)
    return [[0,1],[0,-1],[1,0],[-1,0]].include?([s.x-@x,s.y-@y])
  end
  
  def to_s
    return "#{@x}, #{@y}"
  end
end

#This method returns all the possible results of executing action a, being in state s
def transition(s,a)
	
	current_loc = [s.x, s.y]
	if T.include? current_loc #For episodic tasks: if s is a final state, this is absorbing, so the next state is the same whatever action we take, and the reward is always 0
		results = [Result.new(1.0, s, Array.new(RSize, 0))]
	else
		first_result = Result.new(1.0 - PPirate, s.method(a).call(), Array.new(RSize, 0))
		first_result.r[0] = -1
		#first_result.r[0] = 0

		sp = first_result.sp
		loc=[sp.x,sp.y]
		
		results = Array.new
		
		if T.include? loc #If we are at a treasure (that is, a final state)
			first_result.r[1] = R[T.index(loc)]
			results << first_result
			if PPirate > 0
			
				#The pirates had taken half the treasure with probability PPirate
				second_result = Result.new(PPirate, sp, Array.new(RSize, 0))

				second_result.r[0] = -1
				second_result.r[1] = R[T.index(loc)]*0.5

				results << second_result
			end
		else
			results << first_result
		end
		
		if PNoise > 0
			second_result = Result.new(PNoise, s, Array.new(RSize, 0))
			second_result.r[0] = -1

			results << second_result
		end
	end

	return results
end

def create_states()
	states = []
	for i in 0...(Columns)
	  for j in 0...(Rows)
	    states << State.new(i,j)
	  end
  end
  return states
end
  

#returns the initial state
def initial_state()
	return State.new(H[0],H[1])
end

def is_final_state?(r, s)
	result = false
	loc=[s.x,s.y]
	if T.include? loc #If we are at a treasure (that is, a final state)
		result = true
	end
	return result
end

def write_ndu(dirName, s, ndu)
	File.open("#{dirName}/NDU-State-#{s.x},#{s.y}.csv", 'w') do |f|
		f.write("Action; Time penalization; Treasure\n")
		for value in ndu.values
			f.write("#{value.a}; #{value.v[0]}; #{value.v[1]}\n".gsub(".", ","))
			f.write("   Stamping: #{value.stamping}\n")
			f.write("   Stamped:  #{value.stamped}\n")
		end
	end
end

def write_q(dirName, s, a, q)
	File.open("#{dirName}/Q-State-#{s.x},#{s.y}-#{a}.csv", 'w') do |f|
		f.write("Time penalization; Treasure\n")
		for value in q.values
			f.write("#{value.v[0]}; #{value.v[1]}\n".gsub(".", ","))
		end
	end
end

def write_readme(dirName, accuracy, alpha, gamma, epsilon, time, episodes, non_stationary, actions_required, episodes_required)
	File.open("#{dirName}/Readme.txt", 'w') do |f|
		f.write("Multi-objective Q-learning algorithm with stamps.\n")
		f.write("The problem tackled is the one of Deep Sea Treasure (EPISODIC) with probability of getting the wrong path, the first in the repository: http://uob-community.ballarat.edu.au/~pvamplew/MORL.html\n")
		f.write("Accuracy: #{accuracy}\n")
		f.write("Probability of pirates stealing half the treasures: #{PPirate}\n")
		f.write("Alpha: #{alpha}\n")
		f.write("Discount Rate: #{gamma}\n")
		f.write("Epsilon: #{epsilon}\n")
		f.write("Elapsed time: #{time} seconds\n")
		f.write("Episodes: #{episodes}\n")
		f.write("Number of non-stationary policies found during learning: #{non_stationary}\n")
		f.write("Actions required to achieve V(h): #{actions_required}\n")
		f.write("Episodes required to achieve V(h): #{episodes_required}\n")
		f.write("--------------------------------------------------------\n")
	end
end