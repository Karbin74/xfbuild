module xfbuild.BuildTask;

private {
	import xfbuild.GlobalParams;
	import xfbuild.Module;
	import xfbuild.Compiler;
	import xfbuild.Linker;
	import xfbuild.Misc;
	
	//import xf.utils.Profiler;

	import Path = tango.io.Path;
	import tango.io.device.File;
	import tango.io.stream.Buffered;
	import tango.io.stream.Lines;
	import tango.text.Regex;
	import Integer = tango.text.convert.Integer;

	// TODO: better logging
	import tango.io.Stdout;
}


private {
	__gshared Regex depLineRegex;
}

shared static this() {
	//defend.sim.obj.Building defend\sim\obj\Building.d 633668860572812500 defend.Main,defend.sim.Import,defend.sim.obj.House,defend.sim.obj.Citizen,defend.sim.civ.Test,
	//depLineRegex = Regex(`([a-zA-Z0-9._]+)\ ([a-zA-Z0-9.:_\-\\/]+)\ ([0-9]+)\ (.*)`);
}


scope class BuildTask {
	Module[char[]]	modules;
	const(char)[][]	mainFiles;
    bool            doWriteDeps = true;
	//Module[]	moduleStack;
	
	
	this ( bool doWriteDeps, const(char[])[] mainFiles ...) 
    {
        this.doWriteDeps = doWriteDeps;
		this.mainFiles = mainFiles.dup;
		//profile!("BuildTask.readDeps")({
		readDeps();
		//});


	}
	
	
	~this ( ) 
    {
		//profile!("BuildTask.writeDeps")({
        if (this.doWriteDeps)
    		writeDeps();
		//});
	}
	
	
	void execute() {
		//profile!("BuildTask.execute")({
			if(globalParams.nolink)
				compile();
			else
				do compile(); while(link());
		//});
	}
	
	
	void compile() {
		//profile!("BuildTask.compile")({
			//if (moduleStack.length > 0) {
				.compile(modules);
			//}
		//});
	}
	
	
	bool link() {
		if (globalParams.outputFile is null) {
			return false;
		}

		//return profile!("BuildTask.link")({
			return .link(modules,mainFiles);
		//});
	}
	

	private void readDeps() {
		if (globalParams.useDeps && Path.exists(globalParams.depsPath)) {
			scope rawFile = new File(globalParams.depsPath, File.ReadExisting);
			scope file = new BufferedInput(rawFile);
			scope (exit) {
				rawFile.close();
			}
			
			foreach(line; new Lines!(char)(file)) {
				line = TextUtil.trim(line);
				
				if(!line.length)
					continue;
			
				/*auto firstSpace = TextUtil.locate(line, ' ');
				auto thirdSpace = TextUtil.locatePrior(line, ' ');
				auto secondSpace = TextUtil.locatePrior(line, ' ', thirdSpace);
				
				auto name = line[0 .. firstSpace].dup;
				auto path = line[firstSpace + 1 .. secondSpace].dup;
				auto time = Integer.toLong(line[secondSpace + 1 .. thirdSpace]);
				auto deps = line[thirdSpace + 1 .. $].dup;*/
				
				/+if(!depLineRegex.test(line))
					throw new Exception("broken .deps file (line: " ~ line ~ ")");
				
				auto name = depLineRegex[1].dup;
				auto path = depLineRegex[2].dup;
				auto time = Integer.toLong(depLineRegex[3]);
				auto deps = depLineRegex[4].dup;+/
				
				auto arr = line.decomposeString(cast(char[])null, ` `, null, ` `, null, ` `, null);
				if (arr is null) {
					arr = line.decomposeString(cast(char[])null, ` `, null, ` `, null);
				}
				if (arr is null)
					throw new Exception("broken .deps file (line: " ~ line.idup ~ ")");

				auto name = arr[0].dup;
				auto path = arr[1].dup;
				long time;
				try {
					time = Integer.toLong(arr[2]);
				} catch (Exception e) {
					throw new Exception("broken .deps file (line: " ~ line.idup ~ ")");
				}
				auto deps = arr.length > 3 ? arr[3].dup : null;
			
				if(isIgnored(name))
				{
					if(globalParams.verbose)
						Stdout.formatln(name ~ " is ignored");
						
					continue;
				}
			
				//Stdout(time, deps).newline;
			
				if(!Path.exists(path))
					continue;
				
				auto m = new Module;
				m.name = name;
				m.path = path;
				m.timeDep = time;
				m.timeModified = Path.modified(path).ticks;

				if(m.modified && !m.isHeader)
				{
					if(globalParams.verbose)
						Stdout.formatln("{} was modified", m.name);
					
					m.needRecompile = true;
					//moduleStack ~= m;
				}
				else if (globalParams.compilerName != "increBuild") {
					if(!Path.exists(m.objFile))
					{
						if(globalParams.verbose)
							Stdout.formatln("{}'s obj file was removed", m.name);
						
						m.needRecompile = true;
						//moduleStack ~= m;
					}
				}
				
				if (deps) foreach(dep; TextUtil.patterns(deps, ","))
				{
					if(!dep.length)	
						continue;
						
					if(isIgnored(dep))
					{
						if(globalParams.verbose)
							Stdout.formatln(dep ~ " is ignored");
							
						continue;
					}
					
					m.depNames ~= dep;
				}
				
				modules[name.idup] = m;
			}
			
			foreach(m; modules)
			{
				foreach(d; m.depNames)
				{
					auto x = d in modules;
					if(x) m.addDep(*x);
				}
			}
		}


		foreach (mainFile; mainFiles) {
			auto m = Module.fromFile(mainFile);
			
			if (!(m.name in modules)) {
				modules[m.name] = m;
				//moduleStack ~= m;
				m.needRecompile = true;
			}
		}
	}

	private void writeDeps()
	{
		auto rawFile = new File(globalParams.depsPath, File.WriteCreate);
		auto file = new BufferedOutput(rawFile);
		scope(exit) {
			file.flush();
			rawFile.close();
		}
		
		foreach(m; modules) {
			if (m.path.length > 0) {
				file.write(m.name);
				file.write(" ");
				file.write(m.path);
				file.write(" ");
				file.write(Integer.toString(m.timeDep));
				file.write(" ");
				
				foreach(d; m.deps)
				{
					file.write(d.name);
					file.write(",");
				}
				
				file.write("\n");
			}
		}
	}

	void removeObjFiles()
	{
		/*if(Path.exists(objPath))
		{
			foreach(info; Path.children(objPath))
			{
				if(!info.folder && Path.parse(info.name).ext == objExt[1 .. $])
					Path.remove(info.path ~ info.name);
			}
		}*/
		
		foreach(m; modules)
			if(Path.exists(m.objFile))
			{
				Path.remove(m.objFile);
				m.needRecompile = true;
			}
	}
}
