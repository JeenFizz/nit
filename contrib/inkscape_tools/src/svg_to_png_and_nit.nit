# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2012-2015 Alexis Laferrière <alexis.laf@xymus.net>
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

# Extract images of objects from an SVG file using Inkscape
module svg_to_png_and_nit

import opts
import template

# Image information extracted from the SVG file
class Image
	# Name extracted from the object ID minus the `0` prefix and Nit safe
	var name: String

	# Left border
	var x: Int

	# Top border
	var y: Int

	# Image width
	var w: Int

	# Image height
	var h: Int

	# Right border
	fun right: Int do return x+w

	# Bottom border
	fun bottom: Int do return y+h

	redef fun to_s do return name
end

# Document being processed, concerns both the source and the target
class Document
	# Name of the source file
	var drawing_name: String

	# Name of the class to generate
	var nit_class_name: String = drawing_name.capitalized + "Images" is lazy

	# Scaling to apply to the exported image
	var scale: Float

	# Source minimum X
	var min_x: Int

	# Source maximum X
	var max_x: Int

	# Source minimum Y
	var min_y: Int

	# Source maximum Y
	var max_y: Int

	# Get the coordinates for `image` as `"x, y, w, h"`
	fun coordinates(image: Image): String
	do
		var x = image.x.adapt(min_x, scale)
		var y = image.y.adapt(min_y, scale)
		var w = (image.w.to_f*scale).to_i
		var h = (image.h.to_f*scale).to_i

		return "{x}, {y}, {w}, {h}"
	end
end

# Nit module with a single class to retrieve to access the extracted images
abstract class ImageSetSrc
	super Template

	# Target document
	var document: Document

	# Images found in the source document
	var images: Array[Image]
end

# Nit module targeting the MNit framework
class MnitImageSetSrc
	super ImageSetSrc

	redef fun rendering
	do
		# Known array of images
		var arrays_of_images = new Array[String]

		# Attributes of the generated class
		var attributes = new Array[String]

		# Statements for the generated `load_all` method
		var load_exprs = new Array[String]

		# Add images to Nit source file
		for image in images do
			# Adapt coordinates to new top left and scale
			var coordinates = document.coordinates(image)

			var nit_name = image.name
			var last_char = nit_name.chars.last
			if last_char.to_s.is_numeric then
				# Array of images
				# TODO support more than 10 images in an array

				nit_name = nit_name.substring(0, nit_name.length-1)
				if not arrays_of_images.has(nit_name) then
					# Create class attribute to store Array
					arrays_of_images.add(nit_name)
					attributes.add "\tvar {nit_name} = new Array[Image]\n"
				end
				load_exprs.add "\t\t{nit_name}.add(main_image.subimage({coordinates}))\n"
			else
				# Single image
				attributes.add "\tvar {nit_name}: Image is noinit\n"
				load_exprs.add "\t\t{nit_name} = main_image.subimage({coordinates})\n"
			end
		end

		add """
# File generated by svg_to_png_and_nit, do not modify, redef instead

import mnit::image_set

class {{{document.nit_class_name}}}
	super ImageSet

	private var main_image: Image is noinit
"""
		add_all attributes
		add """

	redef fun load_all(app: App)
	do
		main_image = app.load_image(\"images/{{{document.drawing_name}}}.png\")
"""
		add_all load_exprs
		add """
	end
end
"""
	end
end

# Nit module targeting the Gamnit framework
#
# Gamnit's `Texture` already manage the lazy loading, no need to do it here.
class GamnitImageSetSrc
	super ImageSetSrc

	private fun attributes: Array[String]
	do
		# Separate the images from the arrays of images
		var single_images = new Array[Image]
		var arrays_of_images = new HashMap[String, Array[Image]]

		for image in images do
			var nit_name = image.name
			var last_char = nit_name.chars.last
			if last_char.to_s.is_numeric then

				# Is an array
				nit_name = nit_name.substring(0, nit_name.length-1)
				if not arrays_of_images.keys.has(nit_name) then
					# Create a new array
					var array = new Array[Image]
					arrays_of_images[nit_name] = array
				end

				arrays_of_images[nit_name].add image
			else
				# Is a single image
				single_images.add image
			end
		end

		# Attributes of the class
		var attributes = new Array[String]
		attributes.add "\tprivate var main_image = new Texture(\"images/{document.drawing_name}.png\")\n"

		# Add single images to Nit source file
		for image in single_images do
			# Adapt coordinates to new top left and scale
			var coordinates = document.coordinates(image)

			attributes.add "\tvar {image.name}: Texture = main_image.subtexture({coordinates})\n"
		end

		# Add array of images too
		for name, images in arrays_of_images do

			var lines = new Array[String]
			for image in images do
				var coordinates = document.coordinates(image)
				lines.add "\t\tmain_image.subtexture({coordinates})"
			end

			attributes.add """
	var {{{name}}} = new Array[Texture].with_items(
{{{lines.join(",\n")}}})
"""
		end

		return attributes
	end

	redef fun rendering
	do
		add """
# File generated by svg_to_png_and_nit, do not modify, redef instead

import gamnit::display

class {{{document.nit_class_name}}}

"""
		add_all attributes
		add """
end
"""
	end
end

redef class Int
	# Magic adaption of this coordinates to the given `margin` and `scale`
	fun adapt(margin: Int, scale: Float): Int
	do
		var corrected = self-margin
		return (corrected.to_f*scale).to_i
	end

	# The first power of to equal or greater than `self`
	fun next_pow2: Int
	do
		var p = 2
		while p < self do p = p*2
		return p
	end
end

var opt_out_src = new OptionString("Path to output source file (folder or file)", "--src", "-s")
var opt_assets = new OptionString("Path to assert dir where to put PNG files", "--assets", "-a")
var opt_scale = new OptionFloat("Apply scaling to exported images (default at 1.0 of 90dpi)", 1.0, "--scale", "-x")
var opt_gamnit = new OptionBool("Target the Gamnit framework (by default it targets Mnit)", "--gamnit", "-g")
var opt_pow2 = new OptionBool("Round the image size to the next power of 2", "--pow2")
var opt_help = new OptionBool("Print this help message", "--help", "-h")

var opt_context = new OptionContext
opt_context.add_option(opt_out_src, opt_assets, opt_scale, opt_gamnit, opt_pow2, opt_help)

opt_context.parse(args)
var rest = opt_context.rest
var errors = opt_context.errors
if rest.is_empty and not opt_help.value then errors.add "You must specify at least one source drawing file"
if not errors.is_empty or opt_help.value then
	print errors.join("\n")
	print "Usage: svg_to_png_and_nit [Options] drawing.svg [Other files]"
	print "Options:"
	opt_context.usage
	exit 1
end

if not "inkscape".program_is_in_path then
	print "This tool needs the external program `inkscape`, make sure it is installed and in your PATH."
	exit 1
end

var drawings = rest
for drawing in drawings do
	if not drawing.file_exists then
		stderr.write "Source drawing file '{drawing}' does not exist."
		exit 1
	end
end

var assets_path = opt_assets.value
if assets_path == null then assets_path = "assets"
if not assets_path.file_exists then
	stderr.write "Assets dir '{assets_path}' does not exist (use --assets)\n"
	exit 1
end

var src_path = opt_out_src.value
if src_path == null then src_path = "src"
if not src_path.file_exists and src_path.file_extension != "nit" then
	stderr.write "Source dir '{src_path}' does not exist (use --src)\n"
	exit 1
end

var scale = opt_scale.value

for drawing in drawings do
	var drawing_name = drawing.basename(".svg")

	# Get the page dimensions
	# Inkscape doesn't give us this information
	var page_width = -1
	var page_height = -1
	var svg_file = new FileReader.open(drawing)
	while not svg_file.eof do
		var line = svg_file.read_line

		if page_width == -1 and line.search("width") != null then
			var words = line.split("=")
			var n = words[1]
			n = n.substring(1, n.length-2) # remove ""
			page_width = n.to_f.ceil.to_i
		else if page_height == -1 and line.search("height") != null then
			var words = line.split("=")
			var n = words[1]
			n = n.substring(1, n.length-2) # remove ""
			page_height = n.to_f.ceil.to_i
		end
	end
	svg_file.close

	if page_width == -1 or page_height == -1 then
		stderr.write "Source drawing file '{drawing}' doesn't look like an SVG file\n"
		exit 1
	end

	# Query Inkscape
	var prog = "inkscape"
	var proc = new ProcessReader.from_a(prog, ["--without-gui", "--query-all", drawing])

	var min_x = 1000000
	var min_y = 1000000
	var max_x = -1
	var max_y = -1
	var images = new Array[Image]

	# Gather all images beginning with 0
	# also get the bounding box of all images
	while not proc.eof do
		var line = proc.read_line
		var words = line.split(",")

		if words.length == 5 then
			var id = words[0]

			var x = words[1].to_f.floor.to_i
			var y = words[2].to_f.floor.to_i
			var w = words[3].to_f.ceil.to_i+1
			var h = words[4].to_f.ceil.to_i+1

			if id.has_prefix("0") then
				var nit_name = id.substring_from(1)
				nit_name = nit_name.replace('-', "_")

				var image = new Image(nit_name, x, y, w, h)
				min_x = min_x.min(x)
				min_y = min_y.min(y)
				max_x = max_x.max(image.right)
				max_y = max_y.max(image.bottom)

				images.add image
			end
		end
	end
	proc.close


	# Sort images by name, it prevents Array errors and looks better
	alpha_comparator.sort(images)

	var document = new Document(drawing_name, scale, min_x, max_x, min_y, max_y)

	# Nit class
	var nit_src: ImageSetSrc
	if opt_gamnit.value then
		nit_src = new GamnitImageSetSrc(document, images)
	else
		nit_src = new MnitImageSetSrc(document, images)
	end

	if not src_path.file_extension == "nit" then
		src_path = src_path/drawing_name+".nit"
	end

	# Output source file
	var src_file = new FileWriter.open(src_path)
	nit_src.write_to(src_file)
	src_file.close

	# Find next power of 2
	if opt_pow2.value then
		var dx = max_x - min_x
		max_x = dx.next_pow2 + min_x

		var dy = max_y - min_y
		max_y = dy.next_pow2 + min_y
	end

	# Inkscape's --export-area inverts the Y axis. It uses the lower left corner of
	# the drawing area where as queries return coordinates from the top left.
	var y0 = page_height - max_y
	var y1 = page_height - min_y

	# Output png file to assets
	var png_path = "{assets_path}/images/{drawing_name}.png"
	var proc2 = new Process.from_a(prog, [drawing, "--without-gui",
		"--export-dpi={(90.0*scale).to_i}",
		"--export-png={png_path}",
		"--export-area={min_x}:{y0}:{max_x}:{y1}",
		"--export-background=#000000", "--export-background-opacity=0.0"])
	proc2.wait
end
