import { defineExtension } from "lexical"

import { MentionNode } from "#/components/editor/nodes/mention-node.ts"

export const MentionExtension = defineExtension({
  name: "@shadcn-editor/editor/Mention",
  nodes: () => [MentionNode],
})
