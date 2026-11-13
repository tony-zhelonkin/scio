/**
 * Exact line numbers for a local model: `locate` finds a pattern and `lines` prints a numbered range.
 * Both are read-only and clip long lines, so a citation is copied from tool output and never counted.
 */

import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CLIP = 220;
const MAX_HITS = 60;
const MAX_LINES = 120;

const clip = (text: string) => (text.length > CLIP ? `${text.slice(0, CLIP)} …[+${text.length - CLIP} chars]` : text);
const within = (cwd: string, path: string) => (isAbsolute(path) ? path : resolve(cwd, path));
const reply = (text: string) => ({ content: [{ type: "text" as const, text }], details: {} });

const grep = (args: string[]) =>
	new Promise<string>((done) => {
		execFile("grep", args, { maxBuffer: 64 * 1024 * 1024 }, (_error, stdout) => done(stdout));
	});

const locate = defineTool({
	name: "locate",
	label: "Locate",
	description:
		"Find where a name or pattern occurs. Returns one `path:line: text` row per match, with the exact 1-based line number. " +
		"Use it for every line number you cite. `pattern` is an extended regular expression (use `a|b` for alternatives) unless `literal` is true.",
	parameters: Type.Object({
		pattern: Type.String({ description: "Extended regular expression, or a plain string when literal is true" }),
		path: Type.String({ description: "File or directory to search, absolute or relative to the working directory" }),
		literal: Type.Optional(Type.Boolean({ description: "Treat the pattern as a plain string" })),
	}),
	async execute(_id, params, _signal, _update, ctx) {
		const target = within(ctx.cwd, params.path);
		const out = await grep(["-rnI", params.literal ? "-F" : "-E", "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=var", "-e", params.pattern, target]);
		const rows = out.split("\n").filter(Boolean);
		if (!rows.length) return reply(`No match for ${JSON.stringify(params.pattern)} under ${target}.`);
		const shown = rows.slice(0, MAX_HITS).map((row) => {
			const match = row.match(/^(.*?):(\d+):(.*)$/s);
			return match ? `${match[1]}:${match[2]}: ${clip(match[3].trim())}` : clip(row);
		});
		const more = rows.length > MAX_HITS ? `\n[${rows.length - MAX_HITS} more matches not shown; narrow the pattern or the path]` : "";
		return reply(shown.join("\n") + more);
	},
});

const lines = defineTool({
	name: "lines",
	label: "Lines",
	description:
		"Print lines `start` to `end` of a file, each prefixed with its exact 1-based line number as `N| text`. " +
		"Use it to read around a match and to confirm a line number before citing it.",
	parameters: Type.Object({
		path: Type.String({ description: "File path, absolute or relative to the working directory" }),
		start: Type.Number({ description: "First line, 1-based" }),
		end: Type.Number({ description: "Last line, inclusive" }),
	}),
	async execute(_id, params, _signal, _update, ctx) {
		const target = within(ctx.cwd, params.path);
		const all = (await readFile(target, "utf8")).split("\n");
		const start = Math.max(1, Math.floor(params.start));
		const end = Math.min(all.length, Math.floor(params.end), start + MAX_LINES - 1);
		if (start > all.length) return reply(`${target} has ${all.length} lines.`);
		const body = all.slice(start - 1, end).map((text, i) => `${start + i}| ${clip(text)}`);
		return reply(`${target}, lines ${start} to ${end} of ${all.length}\n${body.join("\n")}`);
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(locate);
	pi.registerTool(lines);
}
