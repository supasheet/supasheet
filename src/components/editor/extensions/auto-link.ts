import { $isCodeNode } from "@lexical/code-core"
import {
  AutoLinkExtension as LexicalAutoLinkExtension,
  autoLinkEmailMatcher,
  autoLinkUrlMatcher,
} from "@lexical/link"
import { configExtension, defineExtension } from "lexical"

export const AutoLinkExtension = defineExtension({
  name: "@shadcn-editor/editor/AutoLink",
  dependencies: [
    configExtension(LexicalAutoLinkExtension, {
      excludeParents: [$isCodeNode],
      matchers: [autoLinkUrlMatcher, autoLinkEmailMatcher],
    }),
  ],
})
