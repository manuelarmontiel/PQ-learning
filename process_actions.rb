
sum = 0.0
runs_completed = 13
actual_runs = 0
max = 0
for i in 0..runs_completed
	file = File.new("#{File.dirname(__FILE__)}/Run#{i}/Readme.txt", "r")
	i = 1
	while (i <= 11)
		line = file.gets
		i += 1
	end
	
	list = line.split(":")
	actions = list[1].strip
	if !(actions == "")
		sum += actions.to_f
		actual_runs += 1
		if actions.to_f > max
			max = actions.to_f
		end
	end
	
	file.close
end

if actual_runs > 0
	puts sum/(actual_runs).to_f
	puts "max: #{max}"
	puts "Runs completed: #{actual_runs}"
else
	puts "No runs completed"
end

