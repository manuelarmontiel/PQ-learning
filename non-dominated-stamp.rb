class NonDominated
	attr_accessor :values
	attr_accessor :c
	
	def initialize(values)
		@c=0.2
		@values = computeND(values)
	end
 
	# compute the non-dominated points
	def computeND(values)
		return values if values.size<=1
		
		index = 0
		while (index < ((values.size)-1))
			p = values[index].v
			i = index + 1
			
			dominated = false
			while ((!dominated) and (i < values.size))
				d = dominant(values[index], values[i])
				if d == 0 #points are equal
					#We only store points that differ more than @c, in order to prevent 
					#excessive growing of the non-dominated sets
					values.delete_at(i)
				elsif d == -1 #points[i] is dominant
					values.delete_at(index)
					dominated = true
				elsif d == 1 #points[index] is dominant
					values.delete_at(i)
				else #points are neither equal, nor dominated by the other one
					i += 1
				end
			end
			
			if !dominated
				index += 1
			end
		end
		
		return values
	end
	
	#Returns:: 1 if p1 is dominant, -1 if p2 is dominant, 0 if are equal and nil if neither p1 nor p2 are dominant
	def dominant(v1, v2)
		result = nil
		
		p1_less = false
		p1_bigger = false
		p2_less = false
		p2_bigger = false
		equal = true
		result = nil
		i = 0
		p1 = v1.v
		p2 = v2.v
		while (i < p1.size)
			if (!p1_less and (p1[i] < p2[i]) and ((p1[i] - p2[i]).abs > @c))
				p1_less = true
				p2_bigger = true
				equal = false
			end
			if (!p2_less and (p1[i] > p2[i]) and ((p1[i] - p2[i]).abs > @c))
				p2_less = true
				p1_bigger = true
				equal = false
			end
			
			i += 1
		end
		
		if (p1_bigger and !p1_less)
			result = 1
		elsif (p2_bigger and !p2_less)
			result = -1
		elsif equal
			result = 0
		else
			result = nil
		end

		return result
	end
	
	def to_s
		s = "ND{\n"
		for value in @values
			s += "  "+value.to_s+"\n"
		end
		s += "}"
		return s
	end
	
	# update with a vector or with a non-dominated set
	def update(rOrNDU, s, a, sp, alpha, r = nil)
				
		if rOrNDU.kind_of?(Array) 
			
			r = rOrNDU
			newValues = []
			
			
			@values.each {|value|
				
				new_v = Array.new
				i = 0
				while i < r.size
					new_v << ((value.v[i]*(1 - alpha)) + (r[i]*alpha))
					i+=1
				end
				new_value = value.clone
				new_value.v = new_v

				if !new_value.stamped[sp]
					new_value.stamped[sp] = -1
				end
				
				#We update the stamps that have stamped s,a from sp (that is a final state)
				if !Stamps[[s,a]][sp].include? -1
					Stamps[[s,a]][sp] << -1
				end
					
				#newValues = computeNDvalue(newValues, new_value)
				newValues << new_value
			}
			
			if newValues.empty?
				
				new_v = Array.new
				i = 0
				while i < r.size
					new_v << ((FIXNUM_MIN*(1 - alpha)) + (r[i]*alpha))
					i+=1
				end
				new_value = Value.new(new_v, s, a)
				
				if !new_value.stamped[sp]
					new_value.stamped[sp] = -1
				end
				
				#We update the stamps that have stamped s,a from sp (that is a final state)
				if !Stamps[[s,a]][sp].include? -1
					Stamps[[s,a]][sp] << -1
				end
				
				newValues = [new_value]
			end
			
			newND = NonDominated.new([])
			newND.values = newValues
			return newND
			
		elsif rOrNDU.kind_of? NonDominated
			
			ndu = rOrNDU
			newValues = []
	
			newND = NonDominated.new([])
			if ndu.values.empty?
				@values.each {|value|
					new_v = Array.new
					i = 0
					while i < r.size
						new_v << ((value.v[i]*(1 - alpha)) + (r[i]*alpha))
						i+=1
					end
					new_value = value.clone
					new_value.v = new_v
					#newValues = computeNDvalue(newValues, new_value)
					newValues << new_value
				}
				Stamps[[s,a]].delete(sp)
			else
				
				#First we generate the stamps of sp that have not been generated until now
				stampingValues = {}
				for stamping_value in ndu.values 

					#stamp = stamping_value.stamping[[s,a]]
					stamp = stamping_value.original_value.stamping[[s,a]]
					if !stamp 
						stamp = StampGen.generateStamp
						
						#if !(stamping_value.s == s) #if there is not a cycle
							stamping_value.original_value.stamping[[s,a]] = stamp
							stamping_value.stamping[[s,a]] = stamp
						#end
						
						#We associate the stamp with the state inside which the stamping value is stored
						StateOfStamp[stamp] = sp
					end
					
					#We update the stamps that have stamped s,a from sp
					if !Stamps[[s,a]][sp].include? stamp
						Stamps[[s,a]][sp] << stamp
					end
					
					#This auxiliar structure is for finding the values that have to be copied inside Q
					stampingValues[stamp] = stamping_value
				end
			
				stamped_values = []
				not_stamped_values = []
				
				@values.each {|value|
					if value.stamped[sp] 
						stamped_values << value
					else
						not_stamped_values << value
					end
				}

				stamped_values.each {|value|
					stamping_value = ndu.get_stamping_value(value)
					
					if stamping_value
						new_v = Array.new
						i = 0
						while i < value.v.size
							new_v << ((value.v[i]*(1 - alpha)) + (stamping_value.v[i]*alpha))
							i+=1
						end
						
						new_value = value.clone
						new_value.v = new_v
						
						#newValues = computeNDvalue(newValues, new_value)
						newValues << new_value

					else
						#in case the value has a stamped, but we cannot find a stamping value in NDU, we erase the stamp ¿and do not store the value inside the new Q?
						
						#newValues << value
						Stamps[[s,a]][sp].delete(value.stamped[sp])
					end
					
				}
				
				#We generate the policies (the combinations of stamps) that should exist inside Q
				policies = get_policies(Stamps[[s,a]])
				#puts "policies: #{policies}"
				policies.each {|p|
					#puts "policy: #{p}"
					if !is_policy_included?(newValues, p)
						#Search updating value inside ndu, with the help of the auxiliar structure stampValues
						stamping_value = nil
						i = 0
						found = false
						while (!found and i < p.values.size)
							if stampingValues[p.values[i]]
								stamping_value = stampingValues[p.values[i]]
								found = true
							end
							i += 1
						end
						
						#Search updated value inside not_stamped_values
						i = 0
						found = false
						updated_value = get_updated_value_by_policy(not_stamped_values, p)
						
						if updated_value #updated by other states' values
							if updated_value.stamping[[s,a]] == stamping_value.stamping[[s,a]] #if they are the same value object...
								new_value = updated_value.clone
							else
								new_v = Array.new
								i = 0
								while i < updated_value.v.size
									new_v << ((updated_value.v[i]*(1-alpha)) + (stamping_value.v[i]*alpha))
									i+=1
								end
								new_value = updated_value.clone
								
								if ((s==stamping_value.s) && (a == stamping_value.a))
									new_value.stamping = stamping_value.stamping
								else
									new_value.stamping = Hash.new(nil)
								end
								
								#If there is not a cicle...
								#if !(s == sp)
								#	new_value.stamping = Hash.new(nil)
									#new_value.original_value = nil
								#else #else...
								#	new_value.stamping = stamping_value.stamping
								#end
								new_value.v = new_v
							end
						else
							new_v = Array.new
							i = 0
							while i < r.size
								new_v << ((FIXNUM_MIN*(1 - alpha)) + (stamping_value.v[i]*alpha))
								i+=1
							end
							new_value = Value.new(stamping_value.v, s, a)
						end
						p.keys.each {|key|
							new_value.stamped[key] = p[key]
						}
						#newValues = computeNDvalue(newValues, new_value)
						newValues << new_value
					end
				}
				
				if Stamps[[s,a]][sp].empty?
					Stamps[[s,a]].delete(sp)
				end
			end

			newND.values = newValues
			return newND
		else
			puts "shouldn't be here!"
		end
	end	
	
	def get_policies(stamps)
		if stamps.keys.size == 1
			policies = []
			
			unique_key= stamps.keys[0]
			
			stamps[unique_key].each {|stamp|
				new_policy = {}
				new_policy[unique_key] = stamp
				policies << new_policy
			}
			
			return policies
		else
			policies = []
			
			first_key = stamps.keys[0]
			
			remainder_stamps = stamps.clone
			remainder_stamps.delete(first_key)
			
			partial_policies = get_policies(remainder_stamps)
			
			stamps[first_key].each {|stamp|
				partial_policies.each {|partial_policy|
					new_policy = partial_policy.clone
					new_policy[first_key] = stamp
					policies << new_policy
				}
			}
			return policies
		end
	end
	
	def is_policy_included?(values, policy)
		sorted_policy = policy.values.sort
		found = false
		i = 0
		while (!found and (i < values.size))
						
			if values[i].stamped.values.sort == sorted_policy
				found = true
			end
			i+=1
		end
		
		return found
	end
	
	def get_updated_value_by_policy(values, policy)
		result = nil
		i = 0
		max_common = -1
		while (i < values.size)
			common = 0
			j = 0
			ok = true
			values[i].stamped.each_key {|state|
				if policy[state] == values[i].stamped[state]
					common += 1
				elsif !(values[i].stamped[state] == -1)
					ok = false
				end
					
				j += 1
			}
			if ok
				if common > max_common
					max_common = common
					result = values[i]
				end
			end
			i += 1
		end
		if max_common > 0
			return result
		else 
			return nil
		end
	end
	
	def get_stamping_value(value)
		found = false
		result = nil
		i = 0
		while (!found and (i < @values.size))
			
			if value.stamped[@values[i].s]
				if value.stamped[@values[i].s] == @values[i].stamping[[value.s, value.a]]
					found = true
					result = @values[i]
				end
			end
			
			i += 1
		end
		return result
	end
	
	def get_arbitrary_value()
		value = nil
		if !@values.empty?
			i = rand(@values.size)
			value = @values[i]
			@values.delete_at(i)
		end
		return value
	end
	
	def get_values_stamp(s,a)
		values_with_stamp = Array.new
		values_without_stamp = Array.new
		while (!@values.empty?)
			if @values[0].stamping[[s,a]]
				values_with_stamp << @values[0]
			else
				values_without_stamp << @values[0]
			end
			@values.delete_at(0)
		end
		return [values_with_stamp, values_without_stamp]
	end
	
	def get_stamped_values(s,a,stamp)
		i = 0
		result = Array.new
		while (i < @values.size)
			if @values[i].stamped[[s,a]] == stamp
				result << @values[i]
				@values.delete_at(i)
			else
				i+=1
			end
		end
		return result
	end
	
	
	def computeNDvalue(values, value)

		index2 = 0
		
		add_it = true
		dominated = false
		while ((add_it) and (index2 < values.size))
			d = dominant(value, values[index2])
			if d == 0 #points are equal
				#We only store points that differ more than @c, in order to prevent 
				#excessive growing of the non-dominated sets
				add_it = false
			elsif d == -1 #p2 is dominant
				add_it = false
			elsif d == 1 #p1 is dominant
				values.delete_at(index2)
			else #points are neither equal, nor dominated by the other one
				index2 += 1
			end
		end
		
		if add_it
			values << value
		end
	
		return values
	end
	
	def computeNDvalueResult(values, value)

		index2 = 0
		
		add_it = true
		dominated = false
		while ((add_it) and (index2 < values.size))
			d = dominant(value, values[index2])
			if d == 0 #points are equal
				#We only store points that differ more than @c, in order to prevent 
				#excessive growing of the non-dominated sets
				add_it = false
			elsif d == -1 #p2 is dominant
				add_it = false
			elsif d == 1 #p1 is dominant
				values.delete_at(index2)
			else #points are neither equal, nor dominated by the other one
				index2 += 1
			end
		end
		
		if add_it
			values << value
		end
	
		return [add_it, values]
	end
	
	# multiply by a scalar
	def *(s)
		newND = self.dup
		newND.c = @c
		newValues = []
		newND.values.each { |value|
			new_v = []
			i = 0
			while i < value.v.size
				new_v << (value.v[i] * s)
				i += 1
			end
			new_value = value.clone
			new_value.v = new_v
			if !new_value.original_value
				new_value.original_value = value
			end
			newValues << new_value
		}
		newND.values = newValues
		return newND
	end
	
	# sum a vector
	def sum(v)
	
		newND = self.dup
		newND.c = @c
		newValues = []
		newND.values.each { |value|
			new_v = []
			i = 0
			while i < value.v.size
				new_v << (value.v[i] + v[i])
				i += 1
			end
			new_value = value.clone
			new_value.v = new_v
			if !new_value.original_value
				new_value.original_value = value
			end
			newValues << new_value
		}
		newND.values = newValues
		return newND
	end
end