"use client"

import {
  createContext,
  forwardRef,
  useCallback,
  useContext,
  useId,
  useLayoutEffect,
  useMemo,
  useState,
} from "react"

import * as ReactDOM from "react-dom"

import { cn } from "@/lib/utils"
import {
  type Announcements,
  DndContext,
  type DndContextProps,
  type DragEndEvent,
  DragOverlay,
  type DraggableSyntheticListeners,
  type DropAnimation,
  KeyboardSensor,
  MouseSensor,
  type ScreenReaderInstructions,
  TouchSensor,
  type UniqueIdentifier,
  closestCenter,
  closestCorners,
  defaultDropAnimationSideEffects,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import {
  restrictToHorizontalAxis,
  restrictToParentElement,
  restrictToVerticalAxis,
} from "@dnd-kit/modifiers"
import {
  SortableContext,
  type SortableContextProps,
  arrayMove,
  horizontalListSortingStrategy,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { Slot } from "@radix-ui/react-slot"

import { composeEventHandlers, useComposedRefs } from "#/lib/composition"

const orientationConfig = {
  vertical: {
    modifiers: [restrictToVerticalAxis, restrictToParentElement],
    strategy: verticalListSortingStrategy,
    collisionDetection: closestCenter,
  },
  horizontal: {
    modifiers: [restrictToHorizontalAxis, restrictToParentElement],
    strategy: horizontalListSortingStrategy,
    collisionDetection: closestCenter,
  },
  mixed: {
    modifiers: [restrictToParentElement],
    strategy: undefined,
    collisionDetection: closestCorners,
  },
}

const ROOT_NAME = "Sortable"
const CONTENT_NAME = "SortableContent"
const ITEM_NAME = "SortableItem"
const ITEM_HANDLE_NAME = "SortableItemHandle"
const OVERLAY_NAME = "SortableOverlay"

const SORTABLE_ERRORS = {
  [ROOT_NAME]: `\`${ROOT_NAME}\` components must be within \`${ROOT_NAME}\``,
  [CONTENT_NAME]: `\`${CONTENT_NAME}\` must be within \`${ROOT_NAME}\``,
  [ITEM_NAME]: `\`${ITEM_NAME}\` must be within \`${CONTENT_NAME}\``,
  [ITEM_HANDLE_NAME]: `\`${ITEM_HANDLE_NAME}\` must be within \`${ITEM_NAME}\``,
  [OVERLAY_NAME]: `\`${OVERLAY_NAME}\` must be within \`${ROOT_NAME}\``,
} as const

type SortableRootContextValue<T> = {
  id: string
  items: UniqueIdentifier[]
  modifiers: DndContextProps["modifiers"]
  strategy: SortableContextProps["strategy"]
  activeId: UniqueIdentifier | null
  setActiveId: (id: UniqueIdentifier | null) => void
  getItemValue: (item: T) => UniqueIdentifier
  flatCursor: boolean
}

const SortableRootContext =
  createContext<SortableRootContextValue<unknown> | null>(null)
SortableRootContext.displayName = ROOT_NAME

function useSortableContext(name: keyof typeof SORTABLE_ERRORS) {
  const context = useContext(SortableRootContext)
  if (!context) {
    throw new Error(SORTABLE_ERRORS[name])
  }
  return context
}

type GetItemValue<T> = {
  /**
   * Callback that returns a unique identifier for each sortable item. Required for array of objects.
   * @example getItemValue={(item) => item.id}
   */
  getItemValue: (item: T) => UniqueIdentifier
}

type SortableProps<T> = DndContextProps & {
  value: T[]
  onValueChange?: (items: T[]) => void
  onMove?: (
    event: DragEndEvent & { activeIndex: number; overIndex: number }
  ) => void
  strategy?: SortableContextProps["strategy"]
  orientation?: "vertical" | "horizontal" | "mixed"
  flatCursor?: boolean
} & (T extends object ? GetItemValue<T> : Partial<GetItemValue<T>>)

function Sortable<T>({
  value,
  onValueChange,
  collisionDetection,
  modifiers,
  strategy,
  onMove,
  orientation = "vertical",
  flatCursor = false,
  getItemValue: getItemValueProp,
  accessibility,
  ...sortableProps
}: SortableProps<T>) {
  const id = useId()
  const [activeId, setActiveId] = useState<UniqueIdentifier | null>(null)

  const sensors = useSensors(
    useSensor(MouseSensor),
    useSensor(TouchSensor),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  )
  const config = useMemo(() => orientationConfig[orientation], [orientation])

  const getItemValue = useCallback(
    (item: T): UniqueIdentifier => {
      if (typeof item === "object" && !getItemValueProp) {
        throw new Error("getItemValue is required when using array of objects.")
      }
      return getItemValueProp
        ? getItemValueProp(item)
        : (item as UniqueIdentifier)
    },
    [getItemValueProp]
  )

  const items = useMemo(() => {
    return value.map((item) => getItemValue(item))
  }, [value, getItemValue])

  const onDragEnd = useCallback(
    (event: DragEndEvent) => {
      const { active, over } = event
      if (over && active.id !== over?.id) {
        const activeIndex = value.findIndex(
          (item) => getItemValue(item) === active.id
        )
        const overIndex = value.findIndex(
          (item) => getItemValue(item) === over.id
        )

        if (onMove) {
          onMove({ ...event, activeIndex, overIndex })
        } else {
          onValueChange?.(arrayMove(value, activeIndex, overIndex))
        }
      }
      setActiveId(null)
    },
    [value, onValueChange, onMove, getItemValue]
  )

  const announcements: Announcements = useMemo(
    () => ({
      onDragStart({ active }) {
        const activeValue = active.id.toString()
        return `Grabbed sortable item "${activeValue}". Current position is ${active.data.current?.sortable.index + 1} of ${value.length}. Use arrow keys to move, space to drop.`
      },
      onDragOver({ active, over }) {
        if (over) {
          const overIndex = over.data.current?.sortable.index ?? 0
          const activeIndex = active.data.current?.sortable.index ?? 0
          const moveDirection = overIndex > activeIndex ? "down" : "up"
          const activeValue = active.id.toString()
          return `Sortable item "${activeValue}" moved ${moveDirection} to position ${overIndex + 1} of ${value.length}.`
        }
        return "Sortable item is no longer over a droppable area. Press escape to cancel."
      },
      onDragEnd({ active, over }) {
        const activeValue = active.id.toString()
        if (over) {
          const overIndex = over.data.current?.sortable.index ?? 0
          return `Sortable item "${activeValue}" dropped at position ${overIndex + 1} of ${value.length}.`
        }
        return `Sortable item "${activeValue}" dropped. No changes were made.`
      },
      onDragCancel({ active }) {
        const activeIndex = active.data.current?.sortable.index ?? 0
        const activeValue = active.id.toString()
        return `Sorting cancelled. Sortable item "${activeValue}" returned to position ${activeIndex + 1} of ${value.length}.`
      },
      onDragMove({ active, over }) {
        if (over) {
          const overIndex = over.data.current?.sortable.index ?? 0
          const activeIndex = active.data.current?.sortable.index ?? 0
          const moveDirection = overIndex > activeIndex ? "down" : "up"
          const activeValue = active.id.toString()
          return `Sortable item "${activeValue}" is moving ${moveDirection} to position ${overIndex + 1} of ${value.length}.`
        }
        return "Sortable item is no longer over a droppable area. Press escape to cancel."
      },
    }),
    [value]
  )

  const screenReaderInstructions: ScreenReaderInstructions = useMemo(
    () => ({
      draggable: `
        To pick up a sortable item, press space or enter.
        While dragging, use the ${orientation === "vertical" ? "up and down" : orientation === "horizontal" ? "left and right" : "arrow"} keys to move the item.
        Press space or enter again to drop the item in its new position, or press escape to cancel.
      `,
    }),
    [orientation]
  )

  const contextValue = useMemo(
    () => ({
      id,
      items,
      modifiers: modifiers ?? config.modifiers,
      strategy: strategy ?? config.strategy,
      activeId,
      setActiveId,
      getItemValue,
      flatCursor,
    }),
    [
      id,
      items,
      modifiers,
      strategy,
      config.modifiers,
      config.strategy,
      activeId,
      getItemValue,
      flatCursor,
    ]
  )

  return (
    <SortableRootContext.Provider
      value={contextValue as SortableRootContextValue<unknown>}
    >
      <DndContext
        collisionDetection={collisionDetection ?? config.collisionDetection}
        modifiers={modifiers ?? config.modifiers}
        sensors={sensors}
        {...sortableProps}
        id={id}
        onDragStart={composeEventHandlers(
          sortableProps.onDragStart,
          ({ active }) => setActiveId(active.id)
        )}
        onDragEnd={composeEventHandlers(sortableProps.onDragEnd, onDragEnd)}
        onDragCancel={composeEventHandlers(sortableProps.onDragCancel, () =>
          setActiveId(null)
        )}
        accessibility={{
          announcements,
          screenReaderInstructions,
          ...accessibility,
        }}
      />
    </SortableRootContext.Provider>
  )
}

const SortableContentContext = createContext<boolean>(false)
SortableContentContext.displayName = CONTENT_NAME

type SortableContentProps = React.ComponentPropsWithoutRef<"div"> & {
  strategy?: SortableContextProps["strategy"]
  children: React.ReactNode
  asChild?: boolean
  withoutSlot?: boolean
}

const SortableContent = forwardRef<HTMLDivElement, SortableContentProps>(
  (
    { strategy: strategyProp, asChild, withoutSlot, children, ...contentProps },
    forwardedRef
  ) => {
    const context = useSortableContext(CONTENT_NAME)

    const ContentPrimitive = asChild ? Slot : "div"

    return (
      <SortableContentContext.Provider value={true}>
        <SortableContext
          items={context.items}
          strategy={strategyProp ?? context.strategy}
        >
          {withoutSlot ? (
            children
          ) : (
            <ContentPrimitive {...contentProps} ref={forwardedRef}>
              {children}
            </ContentPrimitive>
          )}
        </SortableContext>
      </SortableContentContext.Provider>
    )
  }
)
SortableContent.displayName = CONTENT_NAME

type SortableItemContextValue = {
  id: string
  attributes: React.HTMLAttributes<HTMLElement>
  listeners: DraggableSyntheticListeners | undefined
  setActivatorNodeRef: (node: HTMLElement | null) => void
  isDragging?: boolean
  disabled?: boolean
}

const SortableItemContext = createContext<SortableItemContextValue | null>(null)
SortableItemContext.displayName = ITEM_NAME

type SortableItemProps = React.ComponentPropsWithoutRef<"div"> & {
  value: UniqueIdentifier
  asHandle?: boolean
  asChild?: boolean
  disabled?: boolean
}

const SortableItem = forwardRef<HTMLDivElement, SortableItemProps>(
  (
    { value, style, asHandle, asChild, disabled, className, ...itemProps },
    forwardedRef
  ) => {
    const inSortableContent = useContext(SortableContentContext)
    const inSortableOverlay = useContext(SortableOverlayContext)

    if (!inSortableContent && !inSortableOverlay) {
      throw new Error(SORTABLE_ERRORS[ITEM_NAME])
    }

    if (value === "") {
      throw new Error(`\`${ITEM_NAME}\` value cannot be an empty string`)
    }

    const context = useSortableContext(ITEM_NAME)
    const id = useId()
    const {
      attributes,
      listeners,
      setNodeRef,
      setActivatorNodeRef,
      transform,
      transition,
      isDragging,
    } = useSortable({ id: value, disabled })

    const composedRef = useComposedRefs(forwardedRef, (node) => {
      if (disabled) return
      setNodeRef(node)
      if (asHandle) setActivatorNodeRef(node)
    })

    const composedStyle = useMemo<React.CSSProperties>(() => {
      return {
        transform: CSS.Translate.toString(transform),
        transition,
        ...style,
      }
    }, [transform, transition, style])

    const itemContext = useMemo<SortableItemContextValue>(
      () => ({
        id,
        attributes,
        listeners,
        setActivatorNodeRef,
        isDragging,
        disabled,
      }),
      [id, attributes, listeners, setActivatorNodeRef, isDragging, disabled]
    )

    const ItemPrimitive = asChild ? Slot : "div"

    return (
      <SortableItemContext.Provider value={itemContext}>
        <ItemPrimitive
          id={id}
          data-dragging={isDragging ? "" : undefined}
          {...itemProps}
          {...(asHandle ? attributes : {})}
          {...(asHandle ? listeners : {})}
          tabIndex={disabled ? undefined : 0}
          ref={composedRef}
          style={composedStyle}
          className={cn(
            "focus-visible:ring-1 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:outline-hidden",
            {
              "touch-none select-none": asHandle,
              "cursor-default": context.flatCursor,
              "data-dragging:cursor-grabbing": !context.flatCursor,
              "cursor-grab": !isDragging && asHandle && !context.flatCursor,
              "opacity-50": isDragging,
              "pointer-events-none opacity-50": disabled,
            },
            className
          )}
        />
      </SortableItemContext.Provider>
    )
  }
)
SortableItem.displayName = ITEM_NAME

type SortableItemHandleProps = React.ComponentPropsWithoutRef<"button"> & {
  asChild?: boolean
}

const SortableItemHandle = forwardRef<
  HTMLButtonElement,
  SortableItemHandleProps
>(({ asChild, disabled, className, ...itemHandleProps }, forwardedRef) => {
  const itemContext = useContext(SortableItemContext)
  if (!itemContext) {
    throw new Error(SORTABLE_ERRORS[ITEM_HANDLE_NAME])
  }
  const context = useSortableContext(ITEM_HANDLE_NAME)

  const isDisabled = disabled ?? itemContext.disabled

  const composedRef = useComposedRefs(forwardedRef, (node) => {
    if (isDisabled) return
    itemContext.setActivatorNodeRef(node)
  })

  const HandlePrimitive = asChild ? Slot : "button"

  return (
    <HandlePrimitive
      type="button"
      aria-controls={itemContext.id}
      data-dragging={itemContext.isDragging ? "" : undefined}
      {...itemHandleProps}
      {...itemContext.attributes}
      {...itemContext.listeners}
      ref={composedRef}
      className={cn(
        "select-none disabled:pointer-events-none disabled:opacity-50",
        context.flatCursor
          ? "cursor-default"
          : "cursor-grab data-dragging:cursor-grabbing",
        className
      )}
      disabled={isDisabled}
    />
  )
})
SortableItemHandle.displayName = ITEM_HANDLE_NAME

const SortableOverlayContext = createContext(false)
SortableOverlayContext.displayName = OVERLAY_NAME

const dropAnimation: DropAnimation = {
  sideEffects: defaultDropAnimationSideEffects({
    styles: {
      active: {
        opacity: "0.4",
      },
    },
  }),
}

type SortableOverlayProps = Omit<
  React.ComponentPropsWithoutRef<typeof DragOverlay>,
  "children"
> & {
  container?: Element | DocumentFragment | null
  children?:
    ((params: { value: UniqueIdentifier }) => React.ReactNode) | React.ReactNode
}

function SortableOverlay({
  container: containerProp,
  children,
  ...overlayProps
}: SortableOverlayProps) {
  const context = useSortableContext(OVERLAY_NAME)

  const [mounted, setMounted] = useState(false)
  useLayoutEffect(() => setMounted(true), [])

  const container =
    containerProp ?? (mounted ? globalThis.document?.body : null)

  if (!container) return null

  return ReactDOM.createPortal(
    <DragOverlay
      dropAnimation={dropAnimation}
      modifiers={context.modifiers}
      className={cn(!context.flatCursor && "cursor-grabbing")}
      {...overlayProps}
    >
      <SortableOverlayContext.Provider value={true}>
        {context.activeId
          ? typeof children === "function"
            ? children({ value: context.activeId })
            : children
          : null}
      </SortableOverlayContext.Provider>
    </DragOverlay>,
    container
  )
}

const Root = Sortable
const Content = SortableContent
const Item = SortableItem
const ItemHandle = SortableItemHandle
const Overlay = SortableOverlay

export {
  Root,
  Content,
  Item,
  ItemHandle,
  Overlay,
  //
  Sortable,
  SortableContent,
  SortableItem,
  SortableItemHandle,
  SortableOverlay,
}
