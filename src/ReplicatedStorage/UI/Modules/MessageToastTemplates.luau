--!strict
-- Named presets for MessageToast (body = muted context, action = highlighted takeaway).

export type ToastVariant = "success" | "error" | "warning" | "info"

export type TemplateOpts = {
	body: string,
	action: string,
	variant: ToastVariant,
}

local DATA: { [string]: TemplateOpts } = {
	-- Plot / equip
	plotFull = {
		body = "All plot slots are in use.",
		action = "Unequip a pet or get more slots.",
		variant = "warning",
	},
	cannotEquip = {
		body = "Can't equip this pet.",
		action = "Plot may be full or it's already active.",
		variant = "warning",
	},

	-- Storage
	inventoryFull = {
		body = "Inventory is full.",
		action = "Delete, sell, or free space to add pets.",
		variant = "warning",
	},
	eggHatchNoSpace = {
		body = "Not enough inventory space to hatch.",
		action = "Free up slots, then try again.",
		variant = "warning",
	},

	-- Rate / loading
	rateLimited = {
		body = "You're doing that too fast.",
		action = "Wait a moment and try again.",
		variant = "info",
	},
	dataNotLoaded = {
		body = "Your data isn't ready yet.",
		action = "Try again in a few seconds.",
		variant = "info",
	},

	-- Success hints (optional)
	equippedOk = {
		body = "Pet equipped.",
		action = "Check your plot!",
		variant = "success",
	},

	lockedOrDelete = {
		body = "Can't delete this pet.",
		action = "It may be locked or missing.",
		variant = "info",
	},
}

local MessageToastTemplates = {}

function MessageToastTemplates.Get(name: string): TemplateOpts?
	return DATA[name]
end

return MessageToastTemplates
