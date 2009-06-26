# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2008 Jean Privat <jean@pryen.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import kernel

class A
	type E: T
	
	readable writable var _e: nullable E = null
end

class B
special A
	init do end
end

class T
	fun foo do 0.output
	init do end
end

class U
special T
	redef fun foo do 1.output
	init do end
end

var b = new B
var t: nullable T
var u: nullable U = new U

b.e = u
#alt1#u = b.e
t = b.e
b.e.foo
