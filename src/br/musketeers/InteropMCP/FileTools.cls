/// IRIS MCP Gateway - file reading tool for the agent's tool surface.
/// An agent governed by a policy has to consult the records that policy
/// names - the restricted lists, the reference tables, the documents it must
/// read before it acts. This tool makes one file reachable and hands the
/// content back; it does not interpret what it read. The agent decides what
/// the content means and which of its tools to call next.
/// Responsibilities:
/// - Read one file, named by its path under a base directory the deployment
///   owns.
/// - Refuse any path that leaves that base directory, so the agent reaches
///   the files it was given and nothing else.
/// - Answer with the content, the path it was read from and its size.
/// The tool reads only: it never writes, so it needs no authorization policy.
Class br.musketeers.InteropMCP.FileTools Extends %AI.Tool
{

/// The directory the agent may read from. The paths it receives are resolved
/// under this directory, and a path that resolves outside it is refused. It is
/// a deployment's directory, not a production's: the files a production names
/// are chosen by the production, the place they live in is chosen by the
/// deployment.
Parameter BaseDirectory = "/home/irisowner/dev/config";

/// The largest file the tool reads, in characters. A longer file is read up
/// to this limit and reported as truncated, so the agent knows it is not
/// seeing all of it.
Parameter MaxCharacters = 200000;

/// Reads the file at Path and returns its content.
/// The path is relative to the base directory. An absolute path, a path that
/// climbs out of the base directory, and a file that is not there are all
/// refused with an error the agent can read.
ClassMethod ReadFile(Path As %String) As %DynamicObject
{
	Set result = ##class(%DynamicObject).%New()

	Set pPath = $ZStrip(Path, "<>W")
	If pPath = "" {
		Do result.%Set("error", "A path is required.")
		Quit result
	}

	// An absolute path is refused before anything else: the agent names a file
	// by its place under the base directory, never by its place in the
	// filesystem.
	If ($Extract(pPath, 1) = "/") || ($Extract(pPath, 1, 2) = "\\") || ($Extract(pPath, 2) = ":") {
		Do result.%Set("error", "Absolute paths are not permitted. Name the file by its path under the base directory.")
		Quit result
	}

	Set base = ##class(%File).NormalizeDirectory(..#BaseDirectory)
	If base = "" {
		Do result.%Set("error", "The base directory does not exist: " _ ..#BaseDirectory)
		Quit result
	}

	// The containment check is on the resolved path, not on the text: a path
	// that climbs out with .. normalizes to something outside the base
	// directory, and that is what is compared here.
	Set full = ##class(%File).NormalizeFilename(base _ pPath)
	If full = "" {
		Do result.%Set("error", "The path could not be resolved: " _ pPath)
		Quit result
	}
	If $Extract(full, 1, $Length(base)) '= base {
		Do result.%Set("error", "The path is outside the base directory: " _ pPath)
		Quit result
	}

	If '##class(%File).Exists(full) {
		Do result.%Set("error", "The file does not exist: " _ pPath)
		Quit result
	}

	Set content = ""
	Set truncated = 0
	Set readError = ""
	Try {
		Set stream = ##class(%Stream.FileCharacter).%New()
		Set stream.TranslateTable = "UTF8"
		Set sc = stream.LinkToFile(full)
		If $$$ISERR(sc) {
			Set readError = "The file could not be opened: " _ pPath
		} Else {
			Do stream.Rewind()
			Set content = stream.Read(..#MaxCharacters)
			Set truncated = 'stream.AtEnd
			Do stream.%Close()
		}
	} Catch ex {
		Set readError = "The file could not be read: " _ pPath
	}
	If readError '= "" {
		Do result.%Set("error", readError)
		Quit result
	}

	Do result.%Set("path", pPath)
	Do result.%Set("resolvedPath", full)
	Do result.%Set("content", content)
	Do result.%Set("size", $Length(content))
	Do result.%Set("truncated", truncated)
	Quit result
}

}
