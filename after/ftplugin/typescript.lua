local capabilities = vim.lsp.protocol.make_client_capabilities()

local id = vim.lsp.start_client({
	name = "pretty-ts-errors",
	cmd = { "ts-node", "/home/gabe/projects/pretty-ts-errors/src/lsp/index.ts", "--stdio" },
	root_dir = vim.fs.dirname(vim.fs.find({ "package.json" }, { upward = true })[1]),
	capabilities = capabilities,
	filetypes = { "typescript", "typescriptreact", "typescript.tsx" },
})

if not id then
	error("Failed to start pretty-ts-errors")
	return
end

local function spread(template)
	local result = {}
	for key, value in pairs(template) do
		result[key] = value
	end

	return function(table)
		for key, value in pairs(table) do
			result[key] = value
		end
		return result
	end
end

local handler_namespace = "pretty-ts-errors.nvim"
local formatDiagnosticsLspMethod = "pretty-ts-errors/formatDiagnostics"
local cache = {}

vim.api.nvim_create_autocmd("BufNew", {
	callback = function(args)
		vim.lsp.buf_attach_client(args.buffer, id)
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local hasAlreadyAttached = vim.diagnostic.handlers[handler_namespace] ~= nil
		if hasAlreadyAttached then
			return
		end

		local lspClient = vim.lsp.get_client_by_id(args.data.client_id)
		if lspClient.name == "pretty-ts-errors" then
			vim.notify("pretty-ts-errors attached")
			vim.diagnostic.handlers[handler_namespace] = {
				show = function(namespace, bufnr, diagnostics, _opts)
					local allowedSources = { "typescript" }

					local lspDiagnostics = {}
					for _, diagnostic in ipairs(diagnostics) do
						local isTsDiagnostic = vim.tbl_contains(allowedSources, diagnostic.source)
						local formattedMessage = cache[diagnostic.message]
						if isTsDiagnostic and formattedMessage == nil then
							table.insert(lspDiagnostics, {
								severity = diagnostic.severity,
								message = diagnostic.message,
								source = diagnostic.source,
								code = diagnostic.code,
								range = {
									start = {
										line = diagnostic.lnum,
										character = diagnostic.col,
									},
									["end"] = {
										line = diagnostic.end_lnum,
										character = diagnostic.end_col,
									},
								},
								tags = diagnostic._tags,
								data = diagnostic,
							})
						end
					end

					lspClient.request(
						formatDiagnosticsLspMethod,
						{ diagnostics = lspDiagnostics, uri = vim.uri_from_bufnr(bufnr) },
						function(error, result)
							if error then
								print("Error formatting diagnostics", error)
								return
							end

							if result == nil then
								print("No result from formatting diagnostics")
								return
							end

							local vimDiagnostics = {}

							for _, diagnostic in ipairs(diagnostics) do
								local formattedDiagnostic = vim.tbl_filter(function(d)
									local isTsDiagnostic = vim.tbl_contains(allowedSources, d.source)
									return not isTsDiagnostic
								end, result.diagnostics)[1]

								if formattedDiagnostic then
									print(vim.inspect(formattedDiagnostic))
									table.insert(vimDiagnostics, {
										severity = formattedDiagnostic.severity,
										message = formattedDiagnostic.message,
										source = formattedDiagnostic.source,
										code = formattedDiagnostic.code,
										lnum = formattedDiagnostic.range.start.line,
										col = formattedDiagnostic.range.start.character,
										end_lnum = formattedDiagnostic.range["end"].line,
										end_col = formattedDiagnostic.range["end"].character,
										_tags = formattedDiagnostic.tags,
										data = formattedDiagnostic.data,
									})
								else
									table.insert(vimDiagnostics, diagnostic)
								end
							end

							-- print(vim.inspect(vimDiagnostics))

							-- for _, diagnostic in ipairs(diagnostics) do
							-- 	table.insert(
							-- 		vimDiagnostics,
							-- 		spread(diagnostic.data)({
							-- 			message = diagnostic.message,
							-- 			source = "pretty-ts-errors",
							-- 		})
							-- 	)
							-- end
							--
							-- print(vim.inspect(result.diagnostics))

							vim.diagnostic.set(namespace, bufnr, vimDiagnostics)
						end
					)

					-- print(vim.inspect({ opts = opts, bufnr = bufnr, diagnostics = diagnostics, namespace = namespace }))
					-- local level = opts[handler_namespace].log_level
					-- local name = vim.diagnostic.get_namespace(namespace).name
					-- local msg = string.format("%d diagnostics in buffer %d from %s", #diagnostics, bufnr, name)
					-- vim.notify(msg, level)
				end,
			}
		end
	end,
})

-- -- Users can configure the handler
-- vim.diagnostic.config({
-- 	[handler_namespace] = {},
-- })
