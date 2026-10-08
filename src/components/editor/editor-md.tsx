import { useMemo } from "react"

import { ClipboardDOMImportExtension } from "@lexical/clipboard"
import {
  ClearEditorExtension,
  HorizontalRuleExtension,
  TabIndentationExtension,
} from "@lexical/extension"
import { HistoryExtension } from "@lexical/history"
import { CheckListExtension, ListExtension } from "@lexical/list"
import {
  $convertFromMarkdownString,
  $convertToMarkdownString,
  CHECK_LIST,
  ELEMENT_TRANSFORMERS,
  MULTILINE_ELEMENT_TRANSFORMERS,
  TEXT_FORMAT_TRANSFORMERS,
  TEXT_MATCH_TRANSFORMERS,
  registerMarkdownShortcuts,
} from "@lexical/markdown"
import type { Transformer } from "@lexical/markdown"
import { LexicalExtensionComposer } from "@lexical/react/LexicalExtensionComposer"
import { OnChangePlugin } from "@lexical/react/LexicalOnChangePlugin"
import { RichTextExtension } from "@lexical/rich-text"
import { TableExtension } from "@lexical/table"
import { defineExtension } from "lexical"

import { AutoLinkExtension } from "#/components/editor/extensions/auto-link"
import { CodeExtension } from "#/components/editor/extensions/code"
import { DragDropPasteExtension } from "#/components/editor/extensions/drag-drop-paste"
import { EmojiExtension } from "#/components/editor/extensions/emoji"
import { FormatStateExtension } from "#/components/editor/extensions/format-state"
import { ImageExtension } from "#/components/editor/extensions/image"
import { LinkExtension } from "#/components/editor/extensions/link"
import { BlockInsert } from "#/components/editor/plugins/block-insert/block-insert-plugin"
import { InsertCodeBlockPlugin } from "#/components/editor/plugins/block-insert/insert-code-block-plugin"
import { InsertHorizontalRulePlugin } from "#/components/editor/plugins/block-insert/insert-horizontal-rule-plugin"
import { InsertImagePlugin } from "#/components/editor/plugins/block-insert/insert-image-plugin"
import { InsertTablePlugin } from "#/components/editor/plugins/block-insert/insert-table-plugin"
import { BulletedListPickerPlugin } from "#/components/editor/plugins/component-picker/bulleted-list-picker-plugin"
import { CheckListPickerPlugin } from "#/components/editor/plugins/component-picker/check-list-picker-plugin"
import { CodePickerPlugin } from "#/components/editor/plugins/component-picker/code-picker-plugin"
import { ComponentPicker } from "#/components/editor/plugins/component-picker/component-picker-plugin"
import { DividerPickerPlugin } from "#/components/editor/plugins/component-picker/divider-picker-plugin"
import { HeadingPickerPlugin } from "#/components/editor/plugins/component-picker/heading-picker-plugin"
import { ImagePickerPlugin } from "#/components/editor/plugins/component-picker/image-picker-plugin"
import { NumberedListPickerPlugin } from "#/components/editor/plugins/component-picker/numbered-list-picker-plugin"
import { ParagraphPickerPlugin } from "#/components/editor/plugins/component-picker/paragraph-picker-plugin"
import { QuotePickerPlugin } from "#/components/editor/plugins/component-picker/quote-picker-plugin"
import { TablePickerPlugin } from "#/components/editor/plugins/component-picker/table-picker-plugin"
import { ContentEditable } from "#/components/editor/plugins/content-editable"
import { DraggableBlockPlugin } from "#/components/editor/plugins/draggable-block-plugin"
import { EmojiPickerPlugin } from "#/components/editor/plugins/emoji-picker-plugin"
import { FloatingToolbarPlugin } from "#/components/editor/plugins/floating/floating-toolbar-plugin"
import { LinkEditorPlugin } from "#/components/editor/plugins/floating/link-editor-plugin"
import { TableHoverActionsPlugin } from "#/components/editor/plugins/floating/table-hover-actions-plugin"
import {
  LanguageProvider,
  useLanguage,
} from "#/components/editor/plugins/i18n-plugin"
import { BlockFormatToolbarPlugin } from "#/components/editor/plugins/toolbar/block-format-toolbar-plugin"
import { LinkToolbarPlugin } from "#/components/editor/plugins/toolbar/link-toolbar-plugin"
import { TextFormatToolbarPlugin } from "#/components/editor/plugins/toolbar/text-format-toolbar-plugin"
import { Toolbar } from "#/components/editor/plugins/toolbar/toolbar-plugin"
import { editorTheme } from "#/components/editor/theme"
import { EMOJI } from "#/components/editor/transformers/emoji-transformer"
import { HR } from "#/components/editor/transformers/horizontal-rule-transformer"
import { IMAGE } from "#/components/editor/transformers/image-transformer"
import { TABLE } from "#/components/editor/transformers/table-transformer"
import { DirectionProvider } from "#/components/ui/direction"

const EDITOR_TRANSFORMERS: Transformer[] = [
  TABLE,
  HR,
  IMAGE,
  EMOJI,
  CHECK_LIST,
  ...ELEMENT_TRANSFORMERS,
  ...MULTILINE_ELEMENT_TRANSFORMERS,
  ...TEXT_FORMAT_TRANSFORMERS,
  ...TEXT_MATCH_TRANSFORMERS,
]

const defaultPlaceholder = "Press / for commands..."

export function Editor({
  name,
  value,
  onChange,
  disabled,
  placeholder = defaultPlaceholder,
}: {
  name?: string
  value: string
  onChange?: (markdown: string) => void
  disabled?: boolean
  placeholder?: string
}) {
  const app = useMemo(
    () =>
      defineExtension({
        name: "@shadcn-editor/editor",
        namespace: name ?? "shadcn-editor",
        editable: !disabled,
        dependencies: [
          RichTextExtension,
          HistoryExtension,
          TabIndentationExtension,
          ListExtension,
          CheckListExtension,
          LinkExtension,
          AutoLinkExtension,
          CodeExtension,
          EmojiExtension,
          TableExtension,
          HorizontalRuleExtension,
          ImageExtension,
          DragDropPasteExtension,
          FormatStateExtension,
          ClearEditorExtension,
          ClipboardDOMImportExtension,
        ],
        $initialEditorState: () => {
          $convertFromMarkdownString(value ?? "", EDITOR_TRANSFORMERS)
        },
        register: (editor) =>
          registerMarkdownShortcuts(editor, EDITOR_TRANSFORMERS),
        theme: editorTheme,
      }),
    [name, disabled]
  )

  return (
    <LanguageProvider>
      <LexicalExtensionComposer extension={app} contentEditable={null}>
        <EditorWrapper disabled={disabled}>
          {!disabled && (
            <Toolbar>
              <BlockFormatToolbarPlugin />
              <TextFormatToolbarPlugin formats="basic" />
              <BlockInsert>
                <InsertCodeBlockPlugin />
                <InsertHorizontalRulePlugin />
                <InsertImagePlugin />
                <InsertTablePlugin />
              </BlockInsert>
            </Toolbar>
          )}
          <div className="relative min-w-0 flex-1 overflow-y-auto">
            <ContentEditable
              variant="draggable"
              placeholder={{ en: placeholder }}
            />
            <DraggableBlockPlugin />
            <FloatingToolbarPlugin>
              <LinkToolbarPlugin />
            </FloatingToolbarPlugin>
            <LinkEditorPlugin />
            <TableHoverActionsPlugin />
            <EmojiPickerPlugin />
            <ComponentPicker>
              <ParagraphPickerPlugin />
              <HeadingPickerPlugin />
              <TablePickerPlugin />
              <NumberedListPickerPlugin />
              <BulletedListPickerPlugin />
              <CheckListPickerPlugin />
              <QuotePickerPlugin />
              <CodePickerPlugin />
              <DividerPickerPlugin />
              <ImagePickerPlugin />
            </ComponentPicker>
          </div>
          <OnChangePlugin
            ignoreSelectionChange
            onChange={(editorState) => {
              editorState.read(() => {
                onChange?.($convertToMarkdownString(EDITOR_TRANSFORMERS))
              })
            }}
          />
        </EditorWrapper>
      </LexicalExtensionComposer>
    </LanguageProvider>
  )
}

function EditorWrapper({
  children,
  disabled,
}: {
  children: React.ReactNode
  disabled?: boolean
}) {
  const { language, dir } = useLanguage()
  return (
    <DirectionProvider direction={dir}>
      <div
        dir={dir}
        lang={language}
        className={`relative flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-lg border border-input dark:bg-input/30 ${disabled ? "" : "h-96"}`}
      >
        {children}
      </div>
    </DirectionProvider>
  )
}
