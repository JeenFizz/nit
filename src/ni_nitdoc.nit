# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Documentation generator for the nit language.
# Generate API documentation in HTML format from nit source code.
module ni_nitdoc

import model_utils
import modelize_property

# The NitdocContext contains all the knowledge used for doc generation
class NitdocContext

	private var toolcontext = new ToolContext
	private var model: Model
	private var mbuilder: ModelBuilder
	private var mainmodule: MModule
	private var class_hierarchy: POSet[MClass]
	private var arguments: Array[String]
	private var output_dir: nullable String
	private var dot_dir: nullable String
	private var share_dir: nullable String
	private var source: nullable String
	private var min_visibility: MVisibility

	private var opt_dir = new OptionString("Directory where doc is generated", "-d", "--dir")
	private var opt_source = new OptionString("What link for source (%f for filename, %l for first line, %L for last line)", "--source")
	private var opt_sharedir = new OptionString("Directory containing the nitdoc files", "--sharedir")
	private var opt_nodot = new OptionBool("Do not generate graphes with graphiviz", "--no-dot")
	private var opt_private: OptionBool = new OptionBool("Generate the private API", "--private")

	private var opt_custom_title: OptionString = new OptionString("Title displayed in the top of the Overview page and as suffix of all page names", "--custom-title")
	private var opt_custom_menu_items: OptionString = new OptionString("Items displayed in menu before the 'Overview' item (Each item must be enclosed in 'li' tags)", "--custom-menu-items")
	private var opt_custom_overview_text: OptionString = new OptionString("Text displayed as introduction of Overview page before the modules list", "--custom-overview-text")
	private var opt_custom_footer_text: OptionString = new OptionString("Text displayed as footer of all pages", "--custom-footer-text")

	init do
		toolcontext.option_context.add_option(opt_dir)
		toolcontext.option_context.add_option(opt_source)
		toolcontext.option_context.add_option(opt_sharedir)
		toolcontext.option_context.add_option(opt_nodot)
		toolcontext.option_context.add_option(opt_private)
		toolcontext.option_context.add_option(opt_custom_title)
		toolcontext.option_context.add_option(opt_custom_footer_text)
		toolcontext.option_context.add_option(opt_custom_overview_text)
		toolcontext.option_context.add_option(opt_custom_menu_items)
		toolcontext.process_options
		self.arguments = toolcontext.option_context.rest

		if arguments.length < 1 then
			print "usage: nitdoc [options] file..."
			toolcontext.option_context.usage
			exit(1)
		end

		model = new Model
		mbuilder = new ModelBuilder(model, toolcontext)
		# Here we load an process all modules passed on the command line
		var mmodules = mbuilder.parse(arguments)
		if mmodules.is_empty then return
		mbuilder.run_phases

		if mmodules.length == 1 then
			mainmodule = mmodules.first
		else
			# We need a main module, so we build it by importing all modules
			mainmodule = new MModule(model, null, "<main>", new Location(null, 0, 0, 0, 0))
			mainmodule.set_imported_mmodules(mmodules)
		end
		self.class_hierarchy = mainmodule.flatten_mclass_hierarchy
		self.process_options
	end

	private fun process_options do
		if not opt_dir.value is null then
			output_dir = opt_dir.value
		else
			output_dir = "doc"
		end
		if not opt_sharedir.value is null then
			share_dir = opt_sharedir.value
		else
			var dir = "NIT_DIR".environ
			if dir.is_empty then
				dir = "{sys.program_name.dirname}/../share/nitdoc"
			else
				dir = "{dir}/share/nitdoc"
			end
			share_dir = dir
			if share_dir is null then
				print "Error: Cannot locate nitdoc share files. Uses --sharedir or envvar NIT_DIR"
				abort
			end
			dir = "{share_dir.to_s}/scripts/js-facilities.js"
			if share_dir is null then
				print "Error: Invalid nitdoc share files. Check --sharedir or envvar NIT_DIR"
				abort
			end

			if opt_private.value then
				min_visibility = none_visibility
			else
				min_visibility = protected_visibility
			end
		end
		source = opt_source.value
	end

	fun generate_nitdoc do
		# Create destination dir if it's necessary
		if not output_dir.file_exists then output_dir.mkdir
		sys.system("cp -r {share_dir.to_s}/* {output_dir.to_s}/")
		self.dot_dir = null
		if not opt_nodot.value then self.dot_dir = output_dir.to_s
		overview
		fullindex
		modules
		classes
		quicksearch_list
	end

	private fun overview do
		var overviewpage = new NitdocOverview(self, dot_dir)
		overviewpage.save("{output_dir.to_s}/index.html")
	end

	private fun fullindex do
		var fullindex = new NitdocFullindex(self)
		fullindex.save("{output_dir.to_s}/full-index.html")
	end

	private fun modules do
		for mmodule in model.mmodules do
			if mmodule.name == "<main>" then continue
			var modulepage = new NitdocModule(mmodule, self, dot_dir)
			modulepage.save("{output_dir.to_s}/{mmodule.url}")
		end
	end

	private fun classes do
		for mclass in mbuilder.model.mclasses do
			var classpage = new NitdocClass(mclass, self, dot_dir, source)
			classpage.save("{output_dir.to_s}/{mclass.url}")
		end
	end

	private fun quicksearch_list do
		var file = new OFStream.open("{output_dir.to_s}/quicksearch-list.js")
		file.write("var entries = \{ ")
		for mmodule in model.mmodules do
			file.write("\"{mmodule.name}\": [")
			file.write("\{txt: \"{mmodule.name}\", url:\"{mmodule.url}\" \},")
			file.write("],")
		end
		for mclass in model.mclasses do
			if mclass.visibility < min_visibility then continue
			file.write("\"{mclass.name}\": [")
			file.write("\{txt: \"{mclass.name}\", url:\"{mclass.url}\" \},")
			file.write("],")
		end
		var name2mprops = new HashMap[String, Set[MPropDef]]
		for mproperty in model.mproperties do
			if mproperty.visibility < min_visibility then continue
			if mproperty isa MAttribute then continue
			if not name2mprops.has_key(mproperty.name) then name2mprops[mproperty.name] = new HashSet[MPropDef]
			name2mprops[mproperty.name].add_all(mproperty.mpropdefs)
		end
		for mproperty, mpropdefs in name2mprops do
			file.write("\"{mproperty}\": [")
			for mpropdef in mpropdefs do
				file.write("\{txt: \"{mpropdef.full_name}\", url:\"{mpropdef.url}\" \},")
			end
			file.write("],")
		end
		file.write(" \};")
		file.close
	end

end

# Nitdoc base page
abstract class NitdocPage

	var dot_dir: nullable String
	var source: nullable String
	var ctx: NitdocContext

	init(ctx: NitdocContext) do
		self.ctx = ctx
	end

	protected fun head do
		append("<meta charset='utf-8'/>")
		append("<script type='text/javascript' src='scripts/jquery-1.7.1.min.js'></script>")
		append("<script type='text/javascript' src='quicksearch-list.js'></script>")
		append("<script type='text/javascript' src='scripts/js-facilities.js'></script>")
		append("<link rel='stylesheet' href='styles/main.css' type='text/css' media='screen'/>")
		var title = ""
		if ctx.opt_custom_title.value != null then
			title = " | {ctx.opt_custom_title.value.to_s}"
		end
		append("<title>{self.title}{title}</title>")
	end

	protected fun menu do
		if ctx.opt_custom_menu_items.value != null then
			append(ctx.opt_custom_menu_items.value.to_s)
		end
	end

	protected fun title: String is abstract

	protected fun header do
		append("<header>")
		append("<nav class='main'>")
		append("<ul>")
		menu
		append("<li id='liGitHub'>")
		append("<a class='btn' id='logGitHub'>")
		append("<img id='imgGitHub' src='resources/icons/github-icon.png' alt='GitHub'/>")
		append("</a>")
		append("<div class='popover bottom'>")
		append("<div class='arrow'>&nbsp;</div>")
		append("<div class='githubTitle'>")
		append("<h3>Github Sign In</h3>")
		append("</div>")
		append("<div>")
		append("<label id='lbloginGit'>Username</label>")
		append("<input id='loginGit' name='login' type='text'/>")
		append("<label id='logginMessage'>Hello ")
		append("<a id='githubAccount'><strong id='nickName'></strong></a>")
		append("</label>")
		append("</div>")
		append("<div>")
		append("<label id='lbpasswordGit'>Password</label>")
		append("<input id='passwordGit' name='password' type='password'/>")
		append("<div id='listBranches'>")
		append("<label id='lbBranches'>Branch</label>")
		append("<select class='dropdown' id='dropBranches' name='dropBranches' tabindex='1'></select>")
		append("</div>")
		append("</div>")
		append("<div>")
		append("<label id='lbrepositoryGit'>Repository</label>")
		append("<input id='repositoryGit' name='repository' type='text'/>")
		append("</div>")
		append("<div>")
		append("<label id='lbbranchGit'>Branch</label>")
		append("<input id='branchGit' name='branch' type='text'/>")
		append("</div>")
		append("<div>")
		append("<a id='signIn'>Sign In</a>")
		append("</div>")
		append("</div>")
		append("</li>")
		append("</ul>")
		append("</nav>")
		append("</header>")
	end

	protected fun content is abstract

	protected fun footer do
		if ctx.opt_custom_footer_text.value != null then
			append("<footer>{ctx.opt_custom_footer_text.value.to_s}</footer>")
		end
	end

	# Generate a clickable graphviz image using a dot content
	protected fun generate_dot(dot: String, name: String, alt: String) do
		var output_dir = dot_dir
		if output_dir == null then return
		var file = new OFStream.open("{output_dir}/{name}.dot")
		file.write(dot)
		file.close
		sys.system("\{ test -f {output_dir}/{name}.png && test -f {output_dir}/{name}.s.dot && diff {output_dir}/{name}.dot {output_dir}/{name}.s.dot >/dev/null 2>&1 ; \} || \{ cp {output_dir}/{name}.dot {output_dir}/{name}.s.dot && dot -Tpng -o{output_dir}/{name}.png -Tcmapx -o{output_dir}/{name}.map {output_dir}/{name}.s.dot ; \}")
		append("<article class='graph'>")
		append("<img src='{name}.png' usemap='#{name}' style='margin:auto' alt='{alt}'/>")
		append("</article>")
		var fmap = new IFStream.open("{output_dir}/{name}.map")
		append(fmap.read_all)
		fmap.close
	end

	# Add a (source) link for a given location
	protected fun show_source(l: Location): String
	do
		if source == null then
			return "({l.file.filename.simplify_path})"
		else
			# THIS IS JUST UGLY ! (but there is no replace yet)
			var x = source.split_with("%f")
			source = x.join(l.file.filename.simplify_path)
			x = source.split_with("%l")
			source = x.join(l.line_start.to_s)
			x = source.split_with("%L")
			source = x.join(l.line_end.to_s)
			return " (<a href=\"{source.to_s}\">source</a>)"
		end
	end

	# Render the page as a html string
	protected fun render do
		append("<!DOCTYPE html>")
		append("<head>")
		head
		append("</head>")
		append("<body>")
		header
		append("<div class='page'>")
		content
		append("</div>")
		footer
		append("</body>")
	end

	# Append a string to the page
	fun append(s: String) do out.write(s)

	# Save html page in the specified file
	fun save(file: String) do
		self.out = new OFStream.open(file)
		render
		self.out.close
	end
	private var out: nullable OFStream
end

# The overview page
class NitdocOverview
	super NitdocPage
	private var mbuilder: ModelBuilder
	private var mmodules = new Array[MModule]

	init(ctx: NitdocContext, dot_dir: nullable String) do
		super(ctx)
		self.mbuilder = ctx.mbuilder
		self.dot_dir = dot_dir
		# get modules
		var mmodules = new HashSet[MModule]
		for mmodule in mbuilder.model.mmodules do
			if mmodule.name == "<main>" then continue
			var owner = mmodule.public_owner
			if owner != null then
				mmodules.add(owner)
			else
				mmodules.add(mmodule)
			end
		end
		# sort modules
		var sorter = new MModuleNameSorter
		self.mmodules.add_all(mmodules)
		sorter.sort(self.mmodules)
	end

	redef fun title do return "Overview"

	redef fun menu do
		super
		append("<li class='current'>Overview</li>")
		append("<li><a href='full-index.html'>Full Index</a></li>")
	end

	redef fun content do
		append("<div class='content fullpage'>")
		var title = "Overview"
		if ctx.opt_custom_title.value != null then
			title = ctx.opt_custom_title.value.to_s
		end
		append("<h1>{title}</h1>")
		var text = ""
		if ctx.opt_custom_overview_text.value != null then
			text = ctx.opt_custom_overview_text.value.to_s
		end
		append("<article class='overview'>{text}</article>")
		append("<article class='overview'>")
		# module list
		append("<h2>Modules</h2>")
		append("<ul>")
		for mmodule in mmodules do
			if mbuilder.mmodule2nmodule.has_key(mmodule) then
				var amodule = mbuilder.mmodule2nmodule[mmodule]
				append("<li>")
				mmodule.html_link(self)
				append("&nbsp;{amodule.short_comment}</li>")
			end
		end
		append("</ul>")
		# module graph
		process_generate_dot
		append("</article>")
		append("</div>")
	end

	private fun process_generate_dot do
		# build poset with public owners
		var poset = new POSet[MModule]
		for mmodule in mmodules do
			poset.add_node(mmodule)
			for omodule in mmodules do
				if mmodule == omodule then continue
				if mmodule.in_importation < omodule then
					poset.add_node(omodule)
					poset.add_edge(mmodule, omodule)
				end
			end
		end
		# build graph
		var op = new Buffer
		op.append("digraph dep \{ rankdir=BT; node[shape=none,margin=0,width=0,height=0,fontsize=10]; edge[dir=none,color=gray]; ranksep=0.2; nodesep=0.1;\n")
		for mmodule in poset do
			op.append("\"{mmodule.name}\"[URL=\"{mmodule.url}\"];\n")
			for omodule in poset[mmodule].direct_greaters do
				op.append("\"{mmodule.name}\"->\"{omodule.name}\";\n")
			end
		end
		op.append("\}\n")
		generate_dot(op.to_s, "dep", "Modules hierarchy")
	end
end

# The full index page
class NitdocFullindex
	super NitdocPage

	init(ctx: NitdocContext) do
		super(ctx)
		self.dot_dir = null
	end

	redef fun title do return "Full Index"

	redef fun menu do
		super
		append("<li><a href='index.html'>Overview</a></li>")
		append("<li class='current'>Full Index</li>")
	end

	redef fun content do
		append("<div class='content fullpage'>")
		append("<h1>Full Index</h1>")
		module_column
		classes_column
		properties_column
		append("</div>")
	end

	# Add to content modules column
	private fun module_column do
		var sorted = ctx.mbuilder.model.mmodule_importation_hierarchy.to_a
		var sorter = new MModuleNameSorter
		sorter.sort(sorted)
		append("<article class='modules filterable'>")
		append("<h2>Modules</h2>")
		append("<ul>")
		for mmodule in sorted do
			append("<li>")
			mmodule.html_link(self)
			append("</li>")
		end
		append("</ul>")
		append("</article>")
	end

	# Add to content classes modules
	private fun classes_column do
		var sorted = ctx.mbuilder.model.mclasses
		var sorter = new MClassNameSorter
		sorter.sort(sorted)
		append("<article class='modules filterable'>")
		append("<h2>Classes</h2>")
		append("<ul>")
		for mclass in sorted do
			if mclass.visibility < ctx.min_visibility then continue
			append("<li>")
			mclass.html_link(self)
			append("</li>")
		end
		append("</ul>")
		append("</article>")
	end

	# Insert the properties column of fullindex page
	private fun properties_column do
		var sorted = ctx.mbuilder.model.mproperties
		var sorter = new MPropertyNameSorter
		sorter.sort(sorted)
		append("<article class='modules filterable'>")
		append("<h2>Properties</h2>")
		append("<ul>")
		for mproperty in sorted do
			if mproperty.visibility < ctx.min_visibility then continue
			if mproperty isa MAttribute then continue
			append("<li>")
			mproperty.intro.html_link(self)
			append(" (")
			mproperty.intro.mclassdef.mclass.html_link(self)
			append(")</li>")
		end
		append("</ul>")
		append("</article>")
	end

end

# A module page
class NitdocModule
	super NitdocPage

	private var mmodule: MModule
	private var mbuilder: ModelBuilder

	init(mmodule: MModule, ctx: NitdocContext, dot_dir: nullable String) do
		super(ctx)
		self.mmodule = mmodule
		self.mbuilder = ctx.mbuilder
		self.dot_dir = dot_dir
	end

	redef fun title do
		if mbuilder.mmodule2nmodule.has_key(mmodule) then
			var nmodule = mbuilder.mmodule2nmodule[mmodule]
			return "{mmodule.name} module | {nmodule.short_comment}"
		else
			return "{mmodule.name} module"
		end
	end

	redef fun menu do
		super
		append("<li><a href='index.html'>Overview</a></li>")
		append("<li class='current'>{mmodule.name}</li>")
		append("<li><a href='full-index.html'>Full Index</a></li>")
	end

	redef fun content do
		sidebar
		append("<div class='content'>")
		append("<h1>{mmodule.name}</h1>")
		append("<div class='subtitle info'>")
		mmodule.html_signature(self)
		append("</div>")
		mmodule.html_full_comment(self)
		process_generate_dot
		classes
		properties
		append("</div>")
	end

	private fun process_generate_dot do
		# build poset with public owners
		var poset = new POSet[MModule]
		for mmodule in self.mmodule.in_importation.poset do
			if mmodule.name == "<main>" then continue
			if mmodule.public_owner != null then continue
			if not mmodule.in_importation < self.mmodule and not self.mmodule.in_importation < mmodule and mmodule != self.mmodule then continue
			poset.add_node(mmodule)
			for omodule in mmodule.in_importation.poset do
				if mmodule == omodule then continue
				if omodule.name == "<main>" then continue
				if omodule.public_owner != null then continue
				if mmodule.in_importation < omodule then
					poset.add_node(omodule)
					poset.add_edge(mmodule, omodule)
				end
			end
		end
		# build graph
		var op = new Buffer
		var name = "dep_{mmodule.name}"
		op.append("digraph {name} \{ rankdir=BT; node[shape=none,margin=0,width=0,height=0,fontsize=10]; edge[dir=none,color=gray]; ranksep=0.2; nodesep=0.1;\n")
		for mmodule in poset do
			if mmodule == self.mmodule then
				op.append("\"{mmodule.name}\"[shape=box,margin=0.03];\n")
			else
				op.append("\"{mmodule.name}\"[URL=\"{mmodule.url}\"];\n")
			end
			for omodule in poset[mmodule].direct_greaters do
				op.append("\"{mmodule.name}\"->\"{omodule.name}\";\n")
			end
		end
		op.append("\}\n")
		generate_dot(op.to_s, name, "Dependency graph for module {mmodule.name}")
	end

	private fun sidebar do
		append("<div class='menu'>")
		append("<nav>")
		append("<h3>Module Hierarchy</h3>")
		var dependencies = new Array[MModule]
		for dep in mmodule.in_importation.greaters do
			if dep == mmodule or dep.public_owner != null then continue
			dependencies.add(dep)
		end
		if dependencies.length > 0 then
			append("<h4>All dependencies</h4>")
			display_module_list(dependencies)
		end
		var clients = new Array[MModule]
		for dep in mmodule.in_importation.smallers do
			if dep.name == "<main>" then continue
			if dep == mmodule or dep.public_owner != null then continue
			clients.add(dep)
		end
		if clients.length > 0 then
			append("<h4>All clients</h4>")
			display_module_list(clients)
		end
		append("</nav>")
		if ctx.min_visibility < protected_visibility then
			if mmodule.in_nesting.direct_greaters.length > 0 then
				append("<nav>")
				append("<h3>Nested Modules</h3>")
				display_module_list(mmodule.in_nesting.direct_greaters.to_a)
				append("</nav>")
			end
		end
		append("</div>")
	end

	private fun display_module_list(list: Array[MModule]) do
		append("<ul>")
		var sorter = new MModuleNameSorter
		sorter.sort(list)
		for m in list do
			append("<li>")
			m.html_link(self)
			append("</li>")
		end
		append("</ul>")
	end

	# display the class column
	private fun classes do
		var intro_mclasses = mmodule.intro_mclasses
		var redef_mclasses = mmodule.redef_mclasses
		var all_mclasses = new HashSet[MClass]
		for m in mmodule.in_nesting.greaters do
			all_mclasses.add_all(m.intro_mclasses)
			all_mclasses.add_all(m.redef_mclasses)
		end
		all_mclasses.add_all(intro_mclasses)
		all_mclasses.add_all(redef_mclasses)

		var sorted = new Array[MClass]
		sorted.add_all(all_mclasses)
		var sorter = new MClassNameSorter
		sorter.sort(sorted)
		append("<div class='module'>")
		append("<article class='classes filterable'>")
		append("<h2>Classes</h2>")
		append("<ul>")
		for c in sorted do
			if c.visibility < ctx.min_visibility then continue
			if redef_mclasses.has(c) and c.intro_mmodule.public_owner != mmodule then
				append("<li class='redef'>")
				append("<span title='refined in this module'>R </span>")
			else
				append("<li class='intro'>")
				append("<span title='introduced in this module'>I </span>")
			end
			c.html_link(self)
			append("</li>")
		end
		append("</ul>")
		append("</article>")
		append("</div>")
	end

	# display the property column
	private fun properties do
		# get properties
		var mpropdefs = new HashSet[MPropDef]
		for m in mmodule.in_nesting.greaters do
			for c in m.mclassdefs do mpropdefs.add_all(c.mpropdefs)
		end
		for c in mmodule.mclassdefs do mpropdefs.add_all(c.mpropdefs)
		var sorted = mpropdefs.to_a
		var sorter = new MPropDefNameSorter
		sorter.sort(sorted)
		# display properties in one column
		append("<article class='properties filterable'>")
		append("<h2>Properties</h2>")
		append("<ul>")
		for mprop in sorted do
			if mprop isa MAttributeDef then continue
			if mprop.mproperty.visibility < ctx.min_visibility then continue
			mprop.html_list_item(self)
		end
		append("</ul>")
		append("</article>")
	end
end

# A class page
class NitdocClass
	super NitdocPage

	private var mclass: MClass
	private var vtypes = new HashSet[MVirtualTypeDef]
	private var consts = new HashSet[MMethodDef]
	private var meths = new HashSet[MMethodDef]
	private var inherited = new HashSet[MPropDef]

	init(mclass: MClass, ctx: NitdocContext, dot_dir: nullable String, source: nullable String) do
		super(ctx)
		self.mclass = mclass
		self.dot_dir = dot_dir
		self.source = source
		# load properties
		for mclassdef in mclass.mclassdefs do
			for mpropdef in mclassdef.mpropdefs do
				if mpropdef.mproperty.visibility < ctx.min_visibility then continue
				if mpropdef isa MVirtualTypeDef then vtypes.add(mpropdef)
				if mpropdef isa MMethodDef then
					if mpropdef.mproperty.is_init then
						consts.add(mpropdef)
					else
						meths.add(mpropdef)
					end
				end
			end
		end
		# get inherited properties
		for pclass in mclass.in_hierarchy(ctx.mainmodule).greaters do
			if pclass == mclass then continue
			for pclassdef in pclass.mclassdefs do
				for mprop in pclassdef.intro_mproperties do
					var mpropdef = mprop.intro
					if mprop.visibility < ctx.min_visibility then continue
					if mpropdef isa MVirtualTypeDef then vtypes.add(mpropdef)
					if mpropdef isa MMethodDef then
						if mpropdef.mproperty.is_init then
							consts.add(mpropdef)
						else
							meths.add(mpropdef)
						end
					end
					inherited.add(mpropdef)
				end
			end
		end
	end

	redef fun title do
		var nclass = ctx.mbuilder.mclassdef2nclassdef[mclass.intro]
		if nclass isa AStdClassdef then
			return "{mclass.name} class | {nclass.short_comment}"
		else
			return "{mclass.name} class"
		end
	end

	redef fun menu do
		super
		append("<li><a href='index.html'>Overview</a></li>")
		var public_owner = mclass.public_owner
		if public_owner is null then
			append("<li>")
			mclass.intro_mmodule.html_link(self)
			append("</li>")
		else
			append("<li>")
			public_owner.html_link(self)
			append("</li>")
		end
		append("<li class='current'>{mclass.name}</li>")
		append("<li><a href='full-index.html'>Full Index</a></li>")
	end

	redef fun content do
		append("<div class='menu'>")
		properties_column
		inheritance_column
		append("</div>")
		append("<div class='content'>")
		class_doc
		append("</div>")
	end

	private fun properties_column do
		var sorter = new MPropDefNameSorter
		append("<nav class='properties filterable'>")
		append("<h3>Properties</h3>")
		# virtual types
		if vtypes.length > 0 then
			var vts = new Array[MVirtualTypeDef]
			vts.add_all(vtypes)
			sorter.sort(vts)
			append("<h4>Virtual Types</h4>")
			append("<ul>")
			for mprop in vts do
				mprop.html_sidebar_item(self)
			end
			append("</ul>")
		end
		# constructors
		if consts.length > 0 then
			var cts = new Array[MMethodDef]
			cts.add_all(consts)
			sorter.sort(cts)
			append("<h4>Constructors</h4>")
			append("<ul>")
			for mprop in cts do
				if mprop.mproperty.name == "init" and mprop.mclassdef.mclass != mclass then continue
				mprop.html_sidebar_item(self)
			end
			append("</ul>")
		end
		# methods
		if meths.length > 0 then
			var mts = new Array[MMethodDef]
			mts.add_all(meths)
			sorter.sort(mts)
			append("<h4>Methods</h4>")
			append("<ul>")
			for mprop in mts do
				if mclass.name != "Object" and mprop.mproperty.intro_mclassdef.mclass.name == "Object" and mprop.mproperty.visibility <= protected_visibility then continue
				mprop.html_sidebar_item(self)
			end
			append("</ul>")
		end
		append("</nav>")
	end

	private fun inheritance_column do
		var sorted = new Array[MClass]
		var sorterp = new MClassNameSorter
		append("<nav>")
		append("<h3>Inheritance</h3>")
		var greaters = mclass.in_hierarchy(ctx.mainmodule).greaters.to_a
		if greaters.length > 1 then
			ctx.mainmodule.linearize_mclasses(greaters)
			append("<h4>Superclasses</h4>")
			append("<ul>")
			for sup in greaters do
				if sup == mclass then continue
				append("<li>")
				sup.html_link(self)
				append("</li>")
			end
			append("</ul>")
		end
		var smallers = mclass.in_hierarchy(ctx.mainmodule).smallers.to_a
		var direct_smallers = mclass.in_hierarchy(ctx.mainmodule).direct_smallers.to_a
		if smallers.length <= 1 then
			append("<h4>No Known Subclasses</h4>")
		else if smallers.length <= 100 then
			ctx.mainmodule.linearize_mclasses(smallers)
			append("<h4>Subclasses</h4>")
			append("<ul>")
			for sub in smallers do
				if sub == mclass then continue
				append("<li>")
				sub.html_link(self)
				append("</li>")
			end
			append("</ul>")
		else if direct_smallers.length <= 100 then
			ctx.mainmodule.linearize_mclasses(direct_smallers)
			append("<h4>Direct Subclasses Only</h4>")
			append("<ul>")
			for sub in direct_smallers do
				if sub == mclass then continue
				append("<li>")
				sub.html_link(self)
				append("</li>")
			end
			append("</ul>")
		else
			append("<h4>Too much Subclasses to list</h4>")
		end
		append("</nav>")
	end

	private fun class_doc do
		# title
		append("<h1>{mclass.signature}</h1>")
		append("<div class='subtitle info'>")
		mclass.html_full_signature(self)
		append("</div>")
		# comment
		var nclass = ctx.mbuilder.mclassdef2nclassdef[mclass.intro]
		append("<div style=\"float: right;\"><a id=\"lblDiffCommit\"></a></div>")
		append("<section class='description'>")
		if nclass isa AStdClassdef and not nclass.full_comment.is_empty then append("<pre class=\"text_label\" title=\"122\" name=\"\" tag=\"{mclass.mclassdefs.first.location.to_s}\" type=\"2\">{nclass.full_comment}</pre><textarea id=\"fileContent\" class=\"edit\" cols=\"76\" rows=\"1\" style=\"display: none;\"></textarea><a id=\"cancelBtn\" style=\"display: none;\">Cancel</a><a id=\"commitBtn\" style=\"display: none;\">Commit</a><pre id=\"preSave\" class=\"text_label\" type=\"2\"></pre>")
		process_generate_dot
		append("</section>")
		# concerns
		var concern2meths = new ArrayMap[MModule, Array[MMethodDef]]
		var sorted_meths = new Array[MMethodDef]
		var sorted = new Array[MModule]
		sorted_meths.add_all(meths)
		ctx.mainmodule.linearize_mpropdefs(sorted_meths)
		for meth in meths do
			if inherited.has(meth) then continue
			var mmodule = meth.mclassdef.mmodule
			if not concern2meths.has_key(mmodule) then
				sorted.add(mmodule)
				concern2meths[mmodule] = new Array[MMethodDef]
			end
			concern2meths[mmodule].add(meth)
		end
		var sections = new ArrayMap[MModule, Array[MModule]]
		for mmodule in concern2meths.keys do
			var owner = mmodule.public_owner
			if owner == null then owner = mmodule
			if not sections.has_key(owner) then sections[owner] = new Array[MModule]
			if owner != mmodule then sections[owner].add(mmodule)
		end
		append("<section class='concerns'>")
		append("<h2 class='section-header'>Concerns</h2>")
		append("<ul>")
		for owner, mmodules in sections do
			var nowner = ctx.mbuilder.mmodule2nmodule[owner]
			append("<li>")
			if nowner.short_comment.is_empty then
				append("<a href=\"#{owner.anchor}\">{owner.name}</a>")
			else
				append("<a href=\"#{owner.anchor}\">{owner.name}</a>: {nowner.short_comment}")
			end
			if not mmodules.is_empty then
				append("<ul>")
				for mmodule in mmodules do
					var nmodule = ctx.mbuilder.mmodule2nmodule[mmodule]
					if nmodule.short_comment.is_empty then
						append("<li><a href=\"#{mmodule.anchor}\">{mmodule.name}</a></li>")
					else
						append("<li><a href=\"#{mmodule.anchor}\">{mmodule.name}</a>: {nmodule.short_comment}</li>")
					end
				end
				append("</ul>")
			end
			append("</li>")
		end
		append("</ul>")
		append("</section>")
		# properties
		var prop_sorter = new MPropDefNameSorter
		var lmmodule = new List[MModule]
		# virtual and formal types
		var local_vtypes = new Array[MVirtualTypeDef]
		for vt in vtypes do if not inherited.has(vt) then local_vtypes.add(vt)
		if local_vtypes.length > 0 or mclass.arity > 0 then
			append("<section class='types'>")
			append("<h2>Formal and Virtual Types</h2>")
			# formal types
			if mclass.arity > 0 and nclass isa AStdClassdef then
				for ft, bound in mclass.parameter_types do
					append("<article id='FT_{ft}'>")
					append("<h3 class='signature'>{ft}: ")
					bound.html_link(self)
					append("</h3>")
					append("<div class=\"info\">formal generic type</div>")
					append("</article>")
				end
			end
			# virtual types
			prop_sorter.sort(local_vtypes)
			for prop in local_vtypes do prop.html_full_desc(self)
			append("</section>")
		end
		# constructors
		var local_consts = new Array[MMethodDef]
		for const in consts do if not inherited.has(const) then local_consts.add(const)
		prop_sorter.sort(local_consts)
		if local_consts.length > 0 then
			append("<section class='constructors'>")
			append("<h2 class='section-header'>Constructors</h2>")
			for prop in local_consts do prop.html_full_desc(self)
			append("</section>")
		end
		# methods
		if not concern2meths.is_empty then
			append("<section class='methods'>")
			append("<h2 class='section-header'>Methods</h2>")
			for owner, mmodules in sections do
				append("<a id=\"{owner.anchor}\"></a>")
				if owner != mclass.intro_mmodule and owner != mclass.public_owner then
					var nowner = ctx.mbuilder.mmodule2nmodule[owner]
					append("<h3 class=\"concern-toplevel\">Methods refined in ")
					owner.html_link(self)
					append("</h3>")
					append("<p class=\"concern-doc\">")
					owner.html_link(self)
					if not nowner.short_comment.is_empty then
						append(": {nowner.short_comment}")
					end
					append("</p>")
				end
				if concern2meths.has_key(owner) then
					var mmethods = concern2meths[owner]
					prop_sorter.sort(mmethods)
					for prop in mmethods do prop.html_full_desc(self)
				end
				for mmodule in mmodules do
					append("<a id=\"{mmodule.anchor}\"></a>")
					var nmodule = ctx.mbuilder.mmodule2nmodule[mmodule]
					if mmodule != mclass.intro_mmodule and mmodule != mclass.public_owner then
						append("<p class=\"concern-doc\">")
						mmodule.html_link(self)
						if not nmodule.short_comment.is_empty then
							append(": {nmodule.short_comment}")
						end
						append("</p>")
					end
					var mmethods = concern2meths[mmodule]
					prop_sorter.sort(mmethods)
					for prop in mmethods do prop.html_full_desc(self)
				end
			end
		end
		# inherited properties
		if inherited.length > 0 then
			var sorted_inherited = new Array[MPropDef]
			sorted_inherited.add_all(inherited)
			ctx.mainmodule.linearize_mpropdefs(sorted_inherited)
			var classes = new ArrayMap[MClass, Array[MPropDef]]
			for mmethod in sorted_inherited.reversed do
				var mclass = mmethod.mclassdef.mclass
				if not classes.has_key(mclass) then classes[mclass] = new Array[MPropDef]
				classes[mclass].add(mmethod)
			end
			append("<h3>Inherited Properties</h3>")
			for c, mmethods in classes do
				prop_sorter.sort(mmethods)
				append("<p>Defined in ")
				c.html_link(self)
				append(": ")
				for i in [0..mmethods.length[ do
					var mmethod = mmethods[i]
					mmethod.html_link(self)
					if i <= mmethods.length - 1 then append(", ")
				end
				append("</p>")
			end
		end
		append("</section>")
	end

	private fun process_generate_dot do
		var pe = ctx.class_hierarchy[mclass]
		var cla = new HashSet[MClass]
		var sm = new HashSet[MClass]
		var sm2 = new HashSet[MClass]
		sm.add(mclass)
		while cla.length + sm.length < 10 and sm.length > 0 do
			cla.add_all(sm)
			sm2.clear
			for x in sm do
				sm2.add_all(pe.poset[x].direct_smallers)
			end
			var t = sm
			sm = sm2
			sm2 = t
		end
		cla.add_all(pe.greaters)

		var op = new Buffer
		var name = "dep_{mclass.name}"
		op.append("digraph {name} \{ rankdir=BT; node[shape=none,margin=0,width=0,height=0,fontsize=10]; edge[dir=none,color=gray]; ranksep=0.2; nodesep=0.1;\n")
		for c in cla do
			if c == mclass then
				op.append("\"{c.name}\"[shape=box,margin=0.03];\n")
			else
				op.append("\"{c.name}\"[URL=\"{c.url}\"];\n")
			end
			for c2 in pe.poset[c].direct_greaters do
				if not cla.has(c2) then continue
				op.append("\"{c.name}\"->\"{c2.name}\";\n")
			end
			if not pe.poset[c].direct_smallers.is_empty then
				var others = true
				for c2 in pe.poset[c].direct_smallers do
					if cla.has(c2) then others = false
				end
				if others then
					op.append("\"{c.name}...\"[label=\"\"];\n")
					op.append("\"{c.name}...\"->\"{c.name}\"[style=dotted];\n")
				end
			end
		end
		op.append("\}\n")
		generate_dot(op.to_s, name, "Dependency graph for class {mclass.name}")
	end
end

#
# Model redefs
#

redef class MModule
	# URL to nitdoc page
	fun url: String do
		if url_cache == null then
			var res = new Buffer
			res.append("module_")
			var mowner = public_owner
			if mowner != null then
				res.append("{public_owner.name}_")
			end
			res.append("{self.name}.html")
			url_cache = res.to_s
		end
		return url_cache.as(not null)
	end
	private var url_cache: nullable String

	# html anchor id to the module in a nitdoc page
	fun anchor: String do
		if anchor_cache == null then
			var res = new Buffer
			res.append("MOD_")
			var mowner = public_owner
			if mowner != null then
				res.append("{public_owner.name}_")
			end
			res.append(self.name)
			anchor_cache = res.to_s
		end
		return anchor_cache.as(not null)
	end
	private var anchor_cache: nullable String

	# Return a link (html a tag) to the nitdoc module page
	fun html_link(page: NitdocPage) do
		if html_link_cache == null then
			var res = new Buffer
			if page.ctx.mbuilder.mmodule2nmodule.has_key(self) then
				res.append("<a href='{url}' title='{page.ctx.mbuilder.mmodule2nmodule[self].short_comment}'>{name}</a>")
			else
				res.append("<a href='{url}'>{name}</a>")
			end
			html_link_cache = res.to_s
		end
		page.append(html_link_cache.as(not null))
	end
	private var html_link_cache: nullable String

	# Return the module signature decorated with html
	fun html_signature(page: NitdocPage) do
		page.append("<span>module ")
		html_full_namespace(page)
		page.append("</span>")
	end

	# Return the module full namespace decorated with html
	fun html_full_namespace(page: NitdocPage) do
		page.append("<span>")
		var mowner = public_owner
		if mowner != null then
			public_owner.html_namespace(page)
			page.append("::")
		end
		html_link(page)
		page.append("</span>")
	end

	# Return the module full namespace decorated with html
	fun html_namespace(page: NitdocPage) do
		page.append("<span>")
		var mowner = public_owner
		if mowner != null then
			public_owner.html_namespace(page)
		else
			html_link(page)
		end
		page.append("</span>")
	end

	# Return the full comment of the module decorated with html
	fun html_full_comment(page: NitdocPage) do
		if page.ctx.mbuilder.mmodule2nmodule.has_key(self) then
			page.append("<div id='description'>")
			page.append("<pre class='text_label'>{page.ctx.mbuilder.mmodule2nmodule[self].full_comment}</pre>")
			page.append("<textarea class='edit' rows='1' cols='76' id='fileContent'></textarea>")
			page.append("<a id='cancelBtn'>Cancel</a>")
			page.append("<a id='commitBtn'>Commit</a>")
			page.append("<pre class='text_label' id='preSave' type='2'></pre>")
			page.append("</div>")
		end
	end
end

redef class MClass
	# Return the module signature decorated with html
	fun html_full_signature(page: NitdocPage) do
		if visibility < public_visibility then page.append("{visibility.to_s} ")
		page.append("{kind} ")
		html_namespace(page)
	end

	# name with formal parameter
	# Foo[A, B]
	private fun signature: String do
		if arity > 0 then
			return "{name}[{intro.parameter_names.join(", ")}]"
		else
			return name
		end
	end

	# Return a link (html a tag) to the nitdoc class page
	fun html_link(page: NitdocPage) do
		if html_link_cache == null then
			var res = new Buffer
			res.append("<a href='{url}'")
			if page.ctx.mbuilder.mclassdef2nclassdef.has_key(intro) then
				var nclass = page.ctx.mbuilder.mclassdef2nclassdef[intro]
				if nclass isa AStdClassdef then
					res.append(" title=\"{nclass.short_comment}\"")
				end
			end
			res.append(">{signature}</a>")
			html_link_cache = res.to_s
		end
		page.append(html_link_cache.as(not null))
	end
	private var html_link_cache: nullable String

	# Return the class namespace decorated with html
	fun html_namespace(page: NitdocPage) do
		intro_mmodule.html_namespace(page)
		page.append("::<span>")
		html_link(page)
		page.append("</span>")
	end

	fun url: String do
		return "class_{public_owner}_{name}.html"
	end

	# Escape name for html output
	redef fun name do return super.html_escape
end

redef class MProperty
	# Return the property namespace decorated with html
	fun html_namespace(page: NitdocPage) do
		intro_mclassdef.mclass.html_namespace(page)
		page.append("::<span>")
		intro.html_link(page)
		page.append("</span>")
	end

	# Escape name for html output
	redef fun name do return super.html_escape
end

redef class MType
	fun html_link(page: NitdocPage) is abstract
end

redef class MClassType
	redef fun html_link(page) do mclass.html_link(page)
end

redef class MNullableType
	redef fun html_link(page) do
		page.append("nullable ")
		mtype.html_link(page)
	end
end

redef class MGenericType
	redef fun html_link(page) do
		page.append("<a href='{mclass.url}'>{mclass.name}</a>[")
		for i in [0..arguments.length[ do
			arguments[i].html_link(page)
			if i < arguments.length - 1 then page.append(", ")
		end
		page.append("]")
	end
end

redef class MParameterType
	redef fun html_link(page) do
		var name = mclass.intro.parameter_names[rank]
		page.append("<a href='{mclass.url}#FT_{name}' title='formal type'>{name}</a>")
	end
end

redef class MVirtualType
	redef fun html_link(page) do mproperty.intro.html_link(page)
end

redef class MClassDef
	# Return the classdef namespace decorated with html
	fun html_namespace(page: NitdocPage) do
		mmodule.html_full_namespace(page)
		page.append("::<span>")
		mclass.html_link(page)
		page.append("</span>")
	end
end

redef class MPropDef
	fun url: String do
		if url_cache == null then
			url_cache = "{mclassdef.mclass.url}#{anchor}"
		end
		return url_cache.as(not null)
	end
	private var url_cache: nullable String

	fun anchor: String do
		if anchor_cache == null then
			anchor_cache = "PROP_{mclassdef.mclass.public_owner.name}_{mproperty.name}"
		end
		return anchor_cache.as(not null)
	end
	private var anchor_cache: nullable String

	# Return a link (html a tag) to the nitdoc class page
	fun html_link(page: NitdocPage) do
		if html_link_cache == null then
			var res = new Buffer
			if page.ctx.mbuilder.mpropdef2npropdef.has_key(self) then
				var nprop = page.ctx.mbuilder.mpropdef2npropdef[self]
				res.append("<a href=\"{url}\" title=\"{nprop.short_comment}\">{mproperty.name}</a>")
			else
				res.append("<a href=\"{url}\">{mproperty.name}</a>")
			end
			html_link_cache = res.to_s
		end
		page.append(html_link_cache.as(not null))
	end
	private var html_link_cache: nullable String

	# Return a list item for the mpropdef
	private fun html_list_item(page: NitdocPage) do
		if is_intro then
			page.append("<li class='intro'>")
			page.append("<span title='introduction'>I</span>&nbsp;")
		else
			page.append("<li class='redef'>")
			page.append("<span title='redefinition'>R</span>&nbsp;")
		end
		html_link(page)
		page.append("(")
		mclassdef.mclass.html_link(page)
		page.append(")")
		page.append("</li>")
	end

	# Return a list item for the mpropdef
	private fun html_sidebar_item(page: NitdocClass) do
		if is_intro and mclassdef.mclass == page.mclass then
			page.append("<li class='intro'>")
			page.append("<span title='Introduced'>I</span>")
		else if is_intro and mclassdef.mclass != page.mclass then
			page.append("<li class='inherit'>")
			page.append("<span title='Inherited'>H</span>")
		else
			page.append("<li class='redef'>")
			page.append("<span title='Redefined'>R</span>")
		end
		html_link(page)
		page.append("</li>")
	end

	private fun html_full_desc(page: NitdocClass) is abstract
	private fun html_info(page: NitdocClass) is abstract

	fun full_name: String do
		return "{mclassdef.mclass.public_owner.name}::{mclassdef.mclass.name}::{mproperty.name}"
	end

	private fun html_inheritance(page: NitdocClass) do
		# definitions block
		page.append("<p class='info'>")
		page.ctx.mainmodule.linearize_mpropdefs(mproperty.mpropdefs)
		var previous_defs = new Array[MPropDef]
		var next_defs = new Array[MPropDef]
		var self_passed = false
		for def in mproperty.mpropdefs do
			if def == self then
				self_passed = true
				continue
			end
			if not self_passed then
				if def.mclassdef.mclass.in_hierarchy(page.ctx.mainmodule) < page.mclass then continue
				if def.is_intro then continue
				previous_defs.add(def)
			else
				if page.mclass.in_hierarchy(page.ctx.mainmodule) < def.mclassdef.mclass then continue
				next_defs.add(def)
			end
		end
		page.append("defined by ")
		mclassdef.mmodule.html_full_namespace(page)
		if page.ctx.mbuilder.mpropdef2npropdef.has_key(self) then
			page.append(" {page.show_source(page.ctx.mbuilder.mpropdef2npropdef[self].location)}")
		end
		if not is_intro then
			page.append(", introduced by ")
			mproperty.intro.mclassdef.mclass.html_link(page)
			if page.ctx.mbuilder.mpropdef2npropdef.has_key(self) then
				page.append(" {page.show_source(page.ctx.mbuilder.mpropdef2npropdef[self].location)}")
			end
		end
		if not previous_defs.is_empty then
			page.append(", inherited from ")
			for i in [0..previous_defs.length[ do
				var def = previous_defs[i]
				def.mclassdef.mclass.html_link(page)
				if page.ctx.mbuilder.mpropdef2npropdef.has_key(def) then
					page.append(" {page.show_source(page.ctx.mbuilder.mpropdef2npropdef[def].location)}")
				end

				if i < previous_defs.length - 1 then page.append(", ")
			end
		end
		if not next_defs.is_empty then
			page.append(", redefined by ")
			for i in [0..next_defs.length[ do
				var def = next_defs[i]
				def.mclassdef.mclass.html_link(page)
				if page.ctx.mbuilder.mpropdef2npropdef.has_key(def) then
					page.append(" {page.show_source(page.ctx.mbuilder.mpropdef2npropdef[def].location)}")
				end
				if i < next_defs.length - 1 then page.append(", ")
			end
		end
		page.append(".</p>")
	end

	private fun html_comment(page: NitdocClass) do
		if not page.ctx.mbuilder.mpropdef2npropdef.has_key(self) then return
		var nprop = page.ctx.mbuilder.mpropdef2npropdef[self]
		page.append("<div class='description'>")
		if not is_intro and page.ctx.mbuilder.mpropdef2npropdef.has_key(mproperty.intro) then
			var intro_nprop = page.ctx.mbuilder.mpropdef2npropdef[mproperty.intro]
			page.append("<p>from ")
			mproperty.html_namespace(page)
			page.append("</p>")
			if intro_nprop.full_comment == "" then
				page.append("<a class=\"newComment\" title=\"32\" tag=\"\">New Comment</a>")
			else
				page.append("<pre class=\"text_label\" title=\"\" name=\"\" tag=\"\" type=\"1\">{intro_nprop.full_comment}</pre>")
			end
			page.append("<p>from ")
			mclassdef.html_namespace(page)
			page.append("</p>")
		end
		if nprop.full_comment == "" then
			page.append("<a class=\"newComment\" title=\"32\" tag=\"\">New Comment</a>")
		else
			page.append("<pre class=\"text_label\" title=\"\" name=\"\" tag=\"\" type=\"1\">{nprop.full_comment}</pre>")
		end
		page.append("<textarea id=\"fileContent\" class=\"edit\" cols=\"76\" rows=\"1\" style=\"display: none;\"></textarea><a id=\"cancelBtn\" style=\"display: none;\">Cancel</a><a id=\"commitBtn\" style=\"display: none;\">Commit</a><pre id=\"preSave\" class=\"text_label\" type=\"2\"></pre>")
		html_inheritance(page)
		page.append("</div>")
	end
end

redef class MMethodDef
	redef fun html_full_desc(page) do
		var classes = new Array[String]
		var is_redef = mproperty.intro_mclassdef.mclass != page.mclass
		if mproperty.is_init then
			classes.add("init")
		else
			classes.add("fun")
		end
		if is_redef then classes.add("redef")
		classes.add(mproperty.visibility.to_s)
		page.append("<article class='{classes.join(" ")}' id='{anchor}'>")
		if page.ctx.mbuilder.mpropdef2npropdef.has_key(self) then
			page.append("<h3 class='signature'>{mproperty.name}")
			msignature.html_signature(page)
			page.append("</h3>")
		else
			page.append("<h3 class='signature'>init")
			msignature.html_signature(page)
			page.append("</h3>")
		end
		html_info(page)
		html_comment(page)
		page.append("</article>")
	end

	redef fun html_info(page) do
		page.append("<div class='info'>")
		if mproperty.visibility < public_visibility then page.append("{mproperty.visibility.to_s} ")
		if mproperty.intro_mclassdef.mclass != page.mclass then page.append("redef ")
		if mproperty.is_init then
			page.append("init ")
		else
			page.append("fun ")
		end
		mproperty.html_namespace(page)
		page.append("</div>")
		page.append("<div style=\"float: right;\"><a id=\"lblDiffCommit\"></a></div>")
	end
end

redef class MVirtualTypeDef
	redef fun html_full_desc(page) do
		var is_redef = mproperty.intro_mclassdef.mclass != page.mclass
		var classes = new Array[String]
		classes.add("type")
		if is_redef then classes.add("redef")
		classes.add(mproperty.visibility.to_s)
		page.append("<article class='{classes.join(" ")}' id='{anchor}'>")
		page.append("<h3 class='signature'>{mproperty.name}: ")
		bound.html_link(page)
		page.append("</h3>")
		html_info(page)
		html_comment(page)
		page.append("</article>")
	end

	redef fun html_info(page) do
		page.append("<div class='info'>")
		if mproperty.intro_mclassdef.mclass != page.mclass then page.append("redef ")
		page.append("type ")
		mproperty.html_namespace(page)
		page.append("</div>")
		page.append("<div style=\"float: right;\"><a id=\"lblDiffCommit\"></a></div>")
	end
end

redef class MSignature
	private fun html_signature(page: NitdocPage) do
		if not mparameters.is_empty then
			page.append("(")
			for i in [0..mparameters.length[ do
				mparameters[i].html_link(page)
				if i < mparameters.length - 1 then page.append(", ")
			end
			page.append(")")
		end
		if return_mtype != null then
			page.append(": ")
			return_mtype.html_link(page)
		end
	end
end

redef class MParameter
	private fun html_link(page: NitdocPage) do
		page.append("{name}: ")
		mtype.html_link(page)
		if is_vararg then page.append("...")
	end
end

#
# Nodes redefs
#

redef class AModule
	private fun short_comment: String do
		if n_moduledecl != null and n_moduledecl.n_doc != null then
			return n_moduledecl.n_doc.n_comment.first.text.substring_from(2).replace("\n", "").html_escape
		end
		return ""
	end

	private fun full_comment: String do
		var res = new Buffer
		if n_moduledecl != null and n_moduledecl.n_doc != null then
			for t in n_moduledecl.n_doc.n_comment do
				res.append(t.text.substring_from(1).html_escape)
			end
		end
		return res.to_s
	end
end

redef class AStdClassdef
	private fun short_comment: String do
		if n_doc != null then return n_doc.n_comment.first.text.substring_from(2).replace("\n", "").html_escape
		return ""
	end

	private fun full_comment: String do
		var res = new Buffer
		if n_doc != null then
			for t in n_doc.n_comment do res.append(t.text.substring_from(1).html_escape)
		end
		return res.to_s
	end
end

redef class APropdef
	private fun short_comment: String do
		if n_doc != null then return n_doc.n_comment.first.text.substring_from(2).replace("\n", "").html_escape
		return ""
	end

	private fun full_comment: String do
		var res = new Buffer
		if n_doc != null then
			for t in n_doc.n_comment do res.append(t.text.substring_from(1).html_escape)
		end
		return res.to_s
	end
end

var nitdoc = new NitdocContext
nitdoc.generate_nitdoc
