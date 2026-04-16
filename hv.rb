front = [[-1,1],[-3,2],[-5,3],[-7,5],[-8,8],[-9,16],[-13,24],[-14,50],[-17,74],[-19,124]]

front.sort! { |a,b| a[0] <=> b[0]}

x0 = -20
y0 = 0
hv = 0

front.each do |value|
	hv += (value[0]-x0) * (value[1] - y0)
	x0 = value[0]
end

puts hv
