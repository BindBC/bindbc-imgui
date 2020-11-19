import std.stdio;
import std.file;
import std.json;
import std.array;
import std.format;
import std.string;
import std.algorithm;
import std.algorithm.searching;
import std.algorithm.iteration;



struct BackendData
{
    string ImplName; // ImplSDL2
    string Name; // SDL2
    string ImportCode; // import bindbc.sdl;
    string VersionDefine; // USE_SDL
}


shared immutable string[string] cArgMap;
shared immutable string[string] cTypeMap;
shared immutable BackendData[string] cBackendMap;

struct code_writer
{
    void put_lines(string aLines)
    {
        foreach (line; std.string.splitLines(aLines))
        {
            write_indent();
            mBuilder.put(line);
            mBuilder.put('\n');
        }
    }

    /// Can be called put once I remove all other uses of the appender other than this class.
    void put_string(string content)
    {
        mBuilder.put(content);
    }
    
    /// Can be called put once I remove all other uses of the appender other than this class.
    void put_string(char content)
    {
        mBuilder.put(content);
    }

    void line_break()
    {
        mBuilder.put('\n');
    }

    void add_extern_c()
    {
        write_indent();
        mBuilder.put("extern (C) @nogc nothrow ");
        add_scope();
    }

    void add_enum()
    {
        write_indent();
        mBuilder.put("enum ");
        add_scope();
    }
    
    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_gshared()
    {
        write_indent();
        mBuilder.put("__gshared ");
        add_scope();
    }

    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_struct(string structName)
    {
        write_indent();
        mBuilder.put("struct ");
        mBuilder.put(structName);
        mBuilder.put(" ");
        add_scope();
    }
    
    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_if(string condition)
    {
        write_indent();
        mBuilder.put("if (");
        mBuilder.put(condition);
        mBuilder.put(") ");
        add_scope();
    }
    
    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_else_f(string condition)
    {
        write_indent();
        mBuilder.put("else if (");
        mBuilder.put(condition);
        mBuilder.put(") ");
        add_scope();
    }
    
    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_else()
    {
        write_indent();
        mBuilder.put("else ");
        add_scope();
    }

    /// Implies add_scope, so must be closed with a RemoveScope;
    void add_version(string versionVar)
    {
        write_indent();
        mBuilder.put("version (");
        mBuilder.put(versionVar);
        mBuilder.put(") ");
        add_scope();
    }

    void add_scope()
    {
        mBuilder.put('{');
        mBuilder.put('\n');
        add_indent();
    }

    void remove_scope()
    {
        remove_indent();
        write_indent();
        mBuilder.put('}');
        mBuilder.put('\n');
    }

    void add_indent()
    {
        ++indent;
    }

    void remove_indent()
    {
        --indent;
    }

    void write_indent()
    {
        string indentStr;
        for (int i = 0; i < indent; ++i)
            mBuilder.put("    ");
    }

    Appender!string mBuilder;
    int indent = 0;
}




shared static this()
{
    cArgMap = [
        "align": "alignment",
        "ref" : "reference",
        "in" : "inItem",
        "out" : "outItem"
    ];
    
    cTypeMap = [
        "unsigned char": "char",
        "unsigned_char": "char",
        "unsigned short": "ushort",
        "unsigned int": "uint",
        "unsigned char*": "char*",
        "unsigned short*": "ushort*",
        "unsigned int*": "uint*",
        "signed char": "byte",
        "signed short": "short",
        "signed int": "int",
        "signed char*": "byte*",
        "signed short*": "short*",
        "signed int*": "int*",
        "int64_t" : "long",
        "uint64_t" : "ulong",
        "union { int BackupInt[2]; float BackupFloat[2];}": "union { int[2] BackupInt; float[2] BackupFloat;}",
        "const char* const[]" : "const(char)**",
        "unsigned char[256]" : "char[256]",
        "unsigned char**" : "char**",
        "const unsigned char[256]" : "const char[256]"
    ];

    cBackendMap = [
        "ImGui_ImplSDL2": BackendData(
            "ImGui_ImplSDL2", 
            "SDL2", 
            "import bindbc.sdl;",
            "USE_SDL2"
        ),
        "ImGui_ImplGlfw" :BackendData(
            "ImGui_ImplGlfw", 
            "Glfw", 
            "import bindbc.sdl;",
            "USE_GLFW"
        ),
        "ImGui_ImplOpenGL2" :BackendData(
            "ImGui_ImplOpenGL2", 
            "OpenGL2", 
            "",
            "USE_OpenGL2"
        ),
        "ImGui_ImplOpenGL3" :BackendData(
            "ImplOpenGL3", 
            "OpenGL3", 
            "",
            "USE_OpenGL3"
        ),
    ];
}

string imgui_argname_to_dlang(string imguiName)
{
    if (auto type = imguiName in cArgMap)
    {
        return *type;
    }

    return imguiName;
}

string imgui_type_to_dlang(string imguiType)
{
    if (auto type = imguiType in cTypeMap)
    {
        return *type;
    }

    imguiType = imguiType.replace("struct ", "");
    imguiType = imguiType.replace("(*)", " function");

    return imguiType;
}

string loaderPrelude = `
module bindbc.imgui.dynload;

version(BindImGui_Static) {}
else:

import bindbc.loader;
import bindbc.imgui.config,
       bindbc.imgui.bind,
       bindbc.imgui.bind.imgui;

private {
    SharedLib lib;
    ImGuiSupport loadedVersion;
}

alias pInitOpenGLForImGui = void function();

__gshared {
pInitOpenGLForImGui InitOpenGLForImGui;
}

bool loadImGuiSupport()
{
    // #1778 prevents me from using static arrays here :(
    version(Windows) {
        const(char)[][1] libNames = [
            "imgui_gl_loader.dll",
        ];
    }
    else version(OSX) {
        const(char)[][1] libNames = [
            "imgui_gl_loader.dylib"
        ];
    }
    else version(Posix) {
        const(char)[][1] libNames = [
            "imgui_gl_loader.so"
        ];
    }
    else static assert(0, "bindbc-ImGui is not yet supported on this platform.");

    bool ret;
    foreach(name; libNames) {
        ret = loadImGuiSupport(name.ptr);
        if(!ret) break;
    }
    return ret;
}

bool loadImGuiSupport(const(char)* libName)
{
    lib = load("imgui_gl_loader.dll");
    if(lib == invalidHandle) {
        return false;
    }

    auto errCount = errorCount();
    loadedVersion = ImGuiSupport.badLibrary;

    lib.bindSymbol(cast(void**)&InitOpenGLForImGui, "InitOpenGLForImGui");

    return true;
}

void unloadImGui()
{
    if(lib != invalidHandle) {
        lib.unload();
    }
}

ImGuiSupport loadedImGuiVersion() { return loadedVersion; }

bool isImGuiLoaded()
{
    return  lib != invalidHandle;
}

ImGuiSupport loadImGui()
{
    // #1778 prevents me from using static arrays here :(
    version(Windows) {
        const(char)[][2] libNames = [
            "cimgui.dll",
            "cimguid.dll",
        ];
    }
    else version(OSX) {
        const(char)[][1] libNames = [
            "cimgui.dylib"
        ];
    }
    else version(Posix) {
        const(char)[][1] libNames = [
            "cimgui.so"
        ];
    }
    else static assert(0, "bindbc-ImGui is not yet supported on this platform.");

    ImGuiSupport ret;
    foreach(name; libNames) {
        ret = loadImGui(name.ptr);
        if(ret != ImGuiSupport.noLibrary) break;
    }

    loadImGuiSupport();

    return ret;
}

ImGuiSupport loadImGui(const(char)* libName)
{
    lib = load(libName);
    if(lib == invalidHandle) {
        return ImGuiSupport.noLibrary;
    }

    auto errCount = errorCount();
    loadedVersion = ImGuiSupport.badLibrary;
`;

string loaderEnd = `

    return loadedVersion;
}
`;

const string imPool = `

struct TypeToReplace {
    TemplatedTypeToReplace Buf;
    ImGuiStorage Map;
    ImPoolIdx FreeIdx;
}

`;


const string imVector = `
struct TypeToReplace {
    int Size;
    int Capacity;
    TemplatedTypeToReplace* Data;
}
`;

const string imChunkStream = `
struct TypeToReplace {
    TemplatedTypeToReplace Buf;
}
`;

const string baseImVector = `
struct ImVector {
    int Size;
    int Capacity;
    void* Data;
}
`;


void write_template_structs(code_writer codeWriter, JSONValue definitions)
{
    string[string] imTemplateTypes;
    auto structs = definitions["structs"];

    imTemplateTypes["ImVector_const_charPtr"] =  "const char*";

    foreach (string structName, JSONValue structMembers; structs) 
    {
        foreach (JSONValue value; structMembers.array)
        {
            //string typeName = imgui_type_to_dlang(value["type"].str);
            //string objectName = value["name"].str;
            //if (startsWith(typeName, "ImVector_"))
            //{
            //    ++imTemplateTypes.length;
            //    imTemplateTypes[imTemplateTypes.length - 1] = imgui_type_to_dlang(typeName["ImVector_".length .. typeName.length]);
            //}

            if ("template_type" in value)
                imTemplateTypes[value["type"].str] =  value["template_type"].str;
        }
    }

    codeWriter.put_lines(baseImVector);

    foreach (string templateName, string templatedOnType; imTemplateTypes)
    {
        string structTemplate;
        if (startsWith(templateName, "ImVector_"))
            structTemplate = imVector;
        else if (startsWith(templateName, "ImPool_"))
            structTemplate = imPool;
        else if (startsWith(templateName, "ImChunkStream_"))
            structTemplate = imChunkStream;

        codeWriter.put_lines(structTemplate.replace("TemplatedTypeToReplace", imgui_type_to_dlang(templatedOnType)).replace("TypeToReplace", templateName));
    }
}

void write_typedefs(code_writer codeWriter, JSONValue typedefs, JSONValue structs_and_enums)
{
    foreach (string typedefName, JSONValue typeDefValue; typedefs) 
    {
        const string originalTypeName = imgui_type_to_dlang(typeDefValue.str);

        if (originalTypeName == "T") continue;
        if (typedefName == "iterator") continue;
        if (typedefName == "const_iterator") continue;

        if (originalTypeName != typedefName)
        {
            string aliasStr = format("alias %s = %s", typedefName,originalTypeName);
            codeWriter.put_string(aliasStr);

            // Sometimes we get a function with a semicolon. so we only sometimes need to write a semicolon.
            if (';'!= aliasStr[aliasStr.length - 1]) codeWriter.put_string(';');
            codeWriter.line_break();
        }

        if ((originalTypeName == typedefName) && !(typedefName in structs_and_enums["structs"]))
            codeWriter.put_lines(format("struct %s;", typedefName));
    }
}

void write_enums(code_writer codeWriter, JSONValue definitions)
{
    auto enums = definitions["enums"];
    foreach (string enumName, JSONValue enumValues; enums) 
    {
        string adjustedName = enumName;

        if ('_' == adjustedName[adjustedName.length - 1])
            adjustedName = adjustedName[0 .. adjustedName.length - 1];

        codeWriter.put_lines(format("alias %s = int;", enumName));
        codeWriter.add_enum();

        foreach (JSONValue value; enumValues.array)
            codeWriter.put_lines(format("%s = %d,\n", value["name"].str, value["calc_value"].integer));

        codeWriter.remove_scope();
        codeWriter.line_break();
    }
}

void write_structs(code_writer codeWriter, JSONValue definitions)
{
    auto structs = definitions["structs"];
    foreach (string structName, JSONValue structMembers; structs) 
    {
        codeWriter.add_struct(structName);

        foreach (JSONValue value; structMembers.array)
        {
            string typeName = imgui_type_to_dlang(value["type"].str);
            string objectName = value["name"].str;

            if ((0 != objectName.length) && (']' == objectName[objectName.length - 1]))
            {
                ptrdiff_t position = std.string.lastIndexOf(objectName, '[');
                typeName = typeName ~ objectName[position .. objectName.length];
                objectName = objectName[0 .. position];
            }
            else
            {

            }

            codeWriter.put_lines(format("%s %s;", typeName, objectName));
        }

        codeWriter.remove_scope();
        codeWriter.line_break();
    }
}


void write_function_loading(code_writer codeWriter, JSONValue definitions)
{
    foreach (string functionName, JSONValue functionDecl; definitions) 
    {
        foreach (JSONValue cimguiFunction; functionDecl.array)
        {
            if ("templated" in cimguiFunction && cimguiFunction["templated"].boolean)
                continue;
                
            codeWriter.put_lines(
                format(
                    "lib.bindSymbol(cast(void**)&%s, \"%s\");", 
                    cimguiFunction["ov_cimguiname"].str, 
                    cimguiFunction["ov_cimguiname"].str));
        }
    }
}

// Return value is the type of the Function pointer, so that it can later be used if we're writing the global symbols to load into.
string write_function(code_writer codeWriter, string functionName, JSONValue cimguiFunction, bool writeFunctionGlobals)
{
    string returnType;

    if ("templated" in cimguiFunction && cimguiFunction["templated"].boolean)
        return "";

    codeWriter.write_indent();

    if ("constructor" in cimguiFunction && cimguiFunction["constructor"].boolean)
        returnType = format("%s*", functionName[0 .. std.string.lastIndexOf(functionName, '_')]);
    else
        returnType = cimguiFunction["ret"].str;

    string functionPtrType = "p" ~ cimguiFunction["ov_cimguiname"].str;
    if (writeFunctionGlobals)
        codeWriter.put_string("alias " ~ functionPtrType ~ " = ");

    codeWriter.put_string(imgui_type_to_dlang(returnType));
    codeWriter.put_string(' ');
    
    if (writeFunctionGlobals)
        codeWriter.put_string("function");
    else
        codeWriter.put_string(cimguiFunction["ov_cimguiname"].str);
    
    codeWriter.put_string("(");

    int i = 0;
    foreach (JSONValue parameter; cimguiFunction["argsT"].array)
    {
        string argType = imgui_type_to_dlang(parameter["type"].str);
        string argName = parameter["name"].str;

        // Deal with arraySubScriptToken in Arg name
        if ((0 != argName.length) && (']' == argName[argName.length - 1]))
        {
            ptrdiff_t position = std.string.lastIndexOf(argName, '[');

            argType = argType ~ argName[position .. argName.length];
            argName = argName[0 .. position];
        }
        
        // Deal with arraySubScriptToken in Arg Type
        if ((0 != argType.length) && (']' == argType[argType.length - 1]))
        {
            ptrdiff_t position = std.string.lastIndexOf(argType, '[');

            const string arraySubScriptToken = argType[position .. argType.length];
            argType = argType ~ "*";

            if (arraySubScriptToken != "[]")
            {
                argType = argType ~ "/*" ~ arraySubScriptToken ~ "*/";
            }
        }

        argName = imgui_argname_to_dlang(argName);
        argType = imgui_type_to_dlang(argType);

        codeWriter.put_string(argType);
        
        if (!startsWith(argType, "..."))
            codeWriter.put_string(' ');

        // Don't write the name out if this function is variadic
        if (argName != "...") codeWriter.put_string(argName);

        // Write out a comma and space if this isn't the last parameter.
        if (++i != cimguiFunction["argsT"].array.length) codeWriter.put_string(", ");
    }
    
    codeWriter.put_string(");");
    codeWriter.line_break();

    return functionPtrType;
}


void write_functions(code_writer codeWriter, JSONValue definitions, bool writeFunctionGlobals)
{
    string[] imFunctionPtrTypes;

    codeWriter.add_extern_c();
    foreach (string functionName, JSONValue functionDecl; definitions)
    {
        if (functionName == "ImVector_ImVector")
            continue;

        foreach (JSONValue cimguiFunction; functionDecl.array)
        {
            const string functionPointerTypeName = write_function(codeWriter, functionName, cimguiFunction, writeFunctionGlobals);

            if (writeFunctionGlobals && (functionPointerTypeName.length != 0))
            {
                ++imFunctionPtrTypes.length;
                imFunctionPtrTypes[imFunctionPtrTypes.length - 1] = functionPointerTypeName;
            }
        }
    }
    
    if (writeFunctionGlobals)
    {
        codeWriter.add_gshared();
        
        foreach (string item; imFunctionPtrTypes)
            codeWriter.put_lines(item ~ " " ~ item[1 .. item.length] ~ ";");

        codeWriter.remove_scope();
    }
    
    codeWriter.remove_scope();
}

void write_backend_functions(code_writer codeWriter, JSONValue definitions, bool writeFunctionGlobals)
{
    struct backend_function
    {
        string functionName;
        JSONValue cimguiFunction;
    }

    // impl to a Backend
    backend_function[][string] backendFunctionsMap;

    foreach (string functionName, JSONValue functionDecl; definitions)
    {
        if (functionName == "ImVector_ImVector")
            continue;


        foreach (JSONValue cimguiFunction; functionDecl.array)
        {
            string implKey = functionName[0 .. std.string.indexOf(functionName, '_', 6)];

            // Init the array if it's not already
            if (!(implKey in backendFunctionsMap)) backendFunctionsMap[implKey] = [];

            ++backendFunctionsMap[implKey].length;
            backendFunctionsMap[implKey][backendFunctionsMap[implKey].length - 1] = backend_function(functionName, cimguiFunction);
        }
    }

    
    codeWriter.add_extern_c();

    foreach (implKey, backendFunctions; backendFunctionsMap)
    {
        if (!(implKey in cBackendMap))
        {
            writeln("WARNING UNKNOWN BACKEND IMPLEMENTATION " ~ implKey ~ ":");

            foreach (backendFunction; backendFunctions)
                writeln("  " ~ backendFunction.functionName);

            continue;
        }

        const auto backendData = cBackendMap[implKey];
        string[] imFunctionPtrTypes;

        codeWriter.add_version(backendData.VersionDefine);
        codeWriter.put_lines(backendData.ImportCode);
        codeWriter.line_break();

        foreach (backendFunction; backendFunctions)
        {
            const string functionPointerTypeName = write_function(
                codeWriter, 
                backendFunction.functionName, 
                backendFunction.cimguiFunction, 
                writeFunctionGlobals);
            
            if (writeFunctionGlobals && (functionPointerTypeName.length != 0))
            {
                ++imFunctionPtrTypes.length;
                imFunctionPtrTypes[imFunctionPtrTypes.length - 1] = functionPointerTypeName;
            }
        }
        
        if (writeFunctionGlobals)
        {
            codeWriter.line_break();
            codeWriter.add_gshared();

            foreach (string item; imFunctionPtrTypes)
                codeWriter.put_lines(item ~ " " ~ item[1 .. item.length] ~ ";");

            codeWriter.remove_scope();
        }

        codeWriter.remove_scope();  // version
    }
    
    codeWriter.remove_scope(); // extern
}


void write_imgui_file(
    JSONValue typedefs_dict,
    JSONValue structs_and_enums,
    JSONValue definitions,
    JSONValue impl_definitions)
{
    auto codeWriter = code_writer();

    codeWriter.put_lines("module bindbc.imgui.bind.imgui;");
    codeWriter.line_break();
    codeWriter.put_lines("import core.stdc.stdio;");
    codeWriter.line_break();
    codeWriter.put_lines("import core.stdc.stdarg;");
    codeWriter.line_break();

    write_typedefs(codeWriter, typedefs_dict, structs_and_enums);
    write_template_structs(codeWriter, structs_and_enums);
    codeWriter.line_break();
    write_enums(codeWriter, structs_and_enums);
    codeWriter.line_break();
    write_structs(codeWriter, structs_and_enums);
    codeWriter.line_break();

    // Writing out the static version of the symbols
    codeWriter.add_version("BindImGui_Static");

    write_functions(codeWriter, definitions, false);
    write_backend_functions(codeWriter, impl_definitions, false);

    // NOTE: For some reason we merge this scope and following else into one line, hence why we're not using remove_scope here.    
    codeWriter.remove_indent();
    codeWriter.put_string("} ");

    // Writing out the Dynamic version of the symbols
    codeWriter.add_else();

    write_functions(codeWriter, definitions, true);
    write_backend_functions(codeWriter, impl_definitions, true);
    
    codeWriter.remove_scope();

    std.file.write("source/bindbc/imgui/bind/imgui.d", codeWriter.mBuilder.data);
}

void write_loader(
    JSONValue definitions,
    JSONValue impl_definitions)
{
    auto codeWriter = code_writer();
    codeWriter.put_lines(loaderPrelude);
    codeWriter.line_break();
    codeWriter.add_indent();

    write_function_loading(codeWriter, definitions);

    codeWriter.line_break();
    codeWriter.put_lines("// Backends");

    write_function_loading(codeWriter, impl_definitions);

    codeWriter.remove_indent();
    codeWriter.put_lines(loaderEnd);
    
    std.file.write("source/bindbc/imgui/dynload.d", codeWriter.mBuilder.data);
}

void main()
{
    JSONValue typedefs_dict = parseJSON(std.file.readText("./deps/cimgui/generator/output/typedefs_dict.json"));
    JSONValue structs_and_enums = parseJSON(std.file.readText("./deps/cimgui/generator/output/structs_and_enums.json"));
    JSONValue definitions = parseJSON(std.file.readText("./deps/cimgui/generator/output/definitions.json"));
    JSONValue impl_definitions = parseJSON(std.file.readText("./deps/cimgui/generator/output/impl_definitions.json"));

    write_loader(definitions, impl_definitions);
    write_imgui_file(typedefs_dict, structs_and_enums, definitions, impl_definitions);

    //JSONValue definitions = parseJSON(std.file.readText("./cimgui/generator/output/definitions.json"));
    //JSONValue impl_definitions = parseJSON(std.file.readText("./cimgui/generator/output/impl_definitions.json"));
    //JSONValue typedefs_dict = parseJSON(std.file.readText("./cimgui/generator/output/typedefs_dict.json"));

    //WriteFunctionBindings(definitions);
    //write_function_loading(impl_definitions);
}