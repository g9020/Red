Red/System [
	Title:   "Red runtime helper functions"
	Author:  "Nenad Rakocevic"
	File: 	 %utils.reds
	Rights:  "Copyright (C) 2011 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/red-system/runtime/BSL-License.txt
	}
]

;-------------------------------------------
;-- Return an integer rounded to the nearest multiple of scale parameter
;-------------------------------------------
round-to: func [
	size 	[integer!]							;-- a memory region size
	scale	[integer!]							;-- scale parameter
	return: [integer!]							;-- nearest scale multiple
][
	assert scale <> 0
	(size + scale) and (negate scale)
]
