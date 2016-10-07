# This file is part of NIT (http://www.nitlanguage.org).
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

# iOS platform support
module ios

import platform
import app

import cocoa::foundation

redef fun print(msg) do msg.to_s.nslog
redef fun print_error(msg) do msg.to_s.nslog

redef class Text
	private fun nslog do to_nsstring.nslog
end

redef class NSString
	private fun nslog in "ObjC" `{ NSLog(@"%@", self); `}
end

redef class NativeString
	# FIXME temp workaround for #1945, bypass Unicode checks
	redef fun char_at(pos) do return self[pos].ascii
end
