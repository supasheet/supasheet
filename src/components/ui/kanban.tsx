import {
  createContext,
  useCallback,
  useContext,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react"

import * as ReactDOM from "react-dom"

import {
  DndContext,
  DragOverlay,
  KeyboardCode,
  KeyboardSensor,
  MeasuringStrategy,
  MouseSensor,
  TouchSensor,
  closestCenter,
  closestCorners,
  defaultDropAnimationSideEffects,
  getFirstCollision,
  pointerWithin,
  rectIntersection,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import type {
  Announcements,
  CollisionDetection,
  DndContextProps,
  DragCancelEvent,
  DragEndEvent,
  DragOverEvent,
  DragStartEvent,
  DraggableAttributes,
  DraggableSyntheticListeners,
  DropAnimation,
  DroppableContainer,
  KeyboardCoordinateGetter,
  UniqueIdentifier,
} from "@dnd-kit/core"
import {
  SortableContext,
  arrayMove,
  defaultAnimateLayoutChanges,
  horizontalListSortingStrategy,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"
import type {
  AnimateLayoutChanges,
  SortableContextProps,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { Slot } from "@radix-ui/react-slot"

import { useComposedRefs } from "#/lib/compose-refs"
import { cn } from "#/lib/utils"

const directions: string[] = [
  KeyboardCode.Down,
  KeyboardCode.Right,
  KeyboardCode.Up,
  KeyboardCode.Left,
]

const coordinateGetter: KeyboardCoordinateGetter = (event, { context }) => {
  const { active, droppableRects, droppableContainers, collisionRect } = context

  if (directions.includes(event.code)) {
    event.preventDefault()

    if (!active || !collisionRect) return

    const filteredContainers: DroppableContainer[] = []

    for (const entry of droppableContainers.getEnabled()) {
      if (!entry || entry?.disabled) continue

      const rect = droppableRects.get(entry.id)
      if (!rect) continue

      const data = entry.data.current
      if (data) {
        const { type, children } = data
        if (type === "container" && children?.length > 0) {
          if (active.data.current?.type !== "container") continue
        }
      }

      switch (event.code) {
        case KeyboardCode.Down:
          if (collisionRect.top < rect.top) filteredContainers.push(entry)
          break
        case KeyboardCode.Up:
          if (collisionRect.top > rect.top) filteredContainers.push(entry)
          break
        case KeyboardCode.Left:
          if (collisionRect.left >= rect.left + rect.width)
            filteredContainers.push(entry)
          break
        case KeyboardCode.Right:
          if (collisionRect.left + collisionRect.width <= rect.left)
            filteredContainers.push(entry)
          break
      }
    }

    const collisions = closestCorners({
      active,
      collisionRect,
      droppableRects,
      droppableContainers: filteredContainers,
      pointerCoordinates: null,
    })
    const closestId = getFirstCollision(collisions, "id")

    if (closestId != null) {
      const newDroppable = droppableContainers.get(closestId)
      const newNode = newDroppable?.node.current
      const newRect = newDroppable?.rect.current

      if (newNode && newRect) {
        if (newDroppable.id === "placeholder") {
          return {
            x: newRect.left + (newRect.width - collisionRect.width) / 2,
            y: newRect.top + (newRect.height - collisionRect.height) / 2,
          }
        }

        if (newDroppable.data.current?.type === "container") {
          return { x: newRect.left + 20, y: newRect.top + 74 }
        }

        return { x: newRect.left, y: newRect.top }
      }
    }
  }

  return undefined
}

const ROOT_NAME = "Kanban"
const BOARD_NAME = "KanbanBoard"
const COLUMN_NAME = "KanbanColumn"
const COLUMN_HANDLE_NAME = "KanbanColumnHandle"
const ITEM_NAME = "KanbanItem"
const ITEM_HANDLE_NAME = "KanbanItemHandle"
const OVERLAY_NAME = "KanbanOverlay"

type KanbanContextValue<T> = {
  id: string
  items: Record<UniqueIdentifier, T[]>
  modifiers: DndContextProps["modifiers"]
  strategy: SortableContextProps["strategy"]
  orientation: "horizontal" | "vertical"
  activeId: UniqueIdentifier | null
  setActiveId: (id: UniqueIdentifier | null) => void
  getItemValue: (item: T) => UniqueIdentifier
  flatCursor: boolean
}

const KanbanContext = createContext<KanbanContextValue<unknown> | null>(null)

function useKanbanContext(consumerName: string) {
  const context = useContext(KanbanContext)
  if (!context) {
    throw new Error(`\`${consumerName}\` must be used within \`${ROOT_NAME}\``)
  }
  return context
}

type GetItemValue<T> = {
  getItemValue: (item: T) => UniqueIdentifier
}

type KanbanRootProps<T> = Omit<DndContextProps, "collisionDetection"> &
  (T extends object ? GetItemValue<T> : Partial<GetItemValue<T>>) & {
    value: Record<UniqueIdentifier, T[]>
    onValueChange?: (columns: Record<UniqueIdentifier, T[]>) => void
    onMove?: (
      event: DragEndEvent & { activeIndex: number; overIndex: number }
    ) => void
    onUpdate?: (item: T, from: UniqueIdentifier, to: UniqueIdentifier) => void
    strategy?: SortableContextProps["strategy"]
    orientation?: "horizontal" | "vertical"
    flatCursor?: boolean
  }

function KanbanRoot<T>({
  value,
  onValueChange,
  modifiers,
  strategy = verticalListSortingStrategy,
  orientation = "horizontal",
  onMove,
  onUpdate,
  getItemValue: getItemValueProp,
  accessibility,
  flatCursor = false,
  ...kanbanProps
}: KanbanRootProps<T>) {
  const id = useId()
  const [activeId, setActiveId] = useState<UniqueIdentifier | null>(null)
  const lastOverIdRef = useRef<UniqueIdentifier | null>(null)
  const hasMovedRef = useRef(false)
  const sensors = useSensors(
    useSensor(MouseSensor),
    useSensor(TouchSensor),
    useSensor(KeyboardSensor, { coordinateGetter })
  )

  const getItemValue = useCallback(
    (item: T): UniqueIdentifier => {
      if (typeof item === "object" && !getItemValueProp) {
        throw new Error("getItemValue is required when using array of objects")
      }
      return getItemValueProp
        ? getItemValueProp(item)
        : (item as UniqueIdentifier)
    },
    [getItemValueProp]
  )

  const getColumn = useCallback(
    (itemId: UniqueIdentifier) => {
      if (itemId in value) return itemId
      for (const [columnId, items] of Object.entries(value)) {
        if (items.some((item) => getItemValue(item) === itemId)) return columnId
      }
      return null
    },
    [value, getItemValue]
  )

  const collisionDetection: CollisionDetection = useCallback(
    (args) => {
      if (activeId && activeId in value) {
        return closestCenter({
          ...args,
          droppableContainers: args.droppableContainers.filter(
            (container) => container.id in value
          ),
        })
      }

      const pointerIntersections = pointerWithin(args)
      const intersections =
        pointerIntersections.length > 0
          ? pointerIntersections
          : rectIntersection(args)
      let overId = getFirstCollision(intersections, "id")

      if (!overId) {
        if (hasMovedRef.current) lastOverIdRef.current = activeId
        return lastOverIdRef.current ? [{ id: lastOverIdRef.current }] : []
      }

      if (overId in value) {
        const containerItems = value[overId]
        if (containerItems && containerItems.length > 0) {
          const closestItem = closestCenter({
            ...args,
            droppableContainers: args.droppableContainers.filter(
              (container) =>
                container.id !== overId &&
                containerItems.some(
                  (item) => getItemValue(item) === container.id
                )
            ),
          })
          if (closestItem.length > 0) overId = closestItem[0]?.id ?? overId
        }
      }

      lastOverIdRef.current = overId
      return [{ id: overId }]
    },
    [activeId, value, getItemValue]
  )

  const onDragStart = useCallback(
    (event: DragStartEvent) => {
      kanbanProps.onDragStart?.(event)
      if (event.activatorEvent.defaultPrevented) return
      setActiveId(event.active.id)
    },
    [kanbanProps.onDragStart]
  )

  const onDragOver = useCallback(
    (event: DragOverEvent) => {
      kanbanProps.onDragOver?.(event)
      if (event.activatorEvent.defaultPrevented) return

      const { active, over } = event
      if (!over) return

      const activeColumn = getColumn(active.id)
      const overColumn = getColumn(over.id)
      if (!activeColumn || !overColumn) return

      if (activeColumn === overColumn) {
        const items = value[activeColumn]
        if (!items) return
        const activeIndex = items.findIndex(
          (item) => getItemValue(item) === active.id
        )
        const overIndex = items.findIndex(
          (item) => getItemValue(item) === over.id
        )
        if (activeIndex !== overIndex) {
          const newColumns = { ...value }
          newColumns[activeColumn] = arrayMove(items, activeIndex, overIndex)
          onValueChange?.(newColumns)
        }
      } else {
        const activeItems = value[activeColumn]
        const overItems = value[overColumn]
        if (!activeItems || !overItems) return

        const activeIndex = activeItems.findIndex(
          (item) => getItemValue(item) === active.id
        )
        if (activeIndex === -1) return

        const activeItem = activeItems[activeIndex]
        if (!activeItem) return

        onUpdate?.(activeItem, activeColumn, overColumn)
        onValueChange?.({
          ...value,
          [activeColumn]: activeItems.filter(
            (item) => getItemValue(item) !== active.id
          ),
          [overColumn]: [...overItems, activeItem],
        })
        hasMovedRef.current = true
      }
    },
    [value, getColumn, getItemValue, onValueChange, kanbanProps.onDragOver]
  )

  const onDragEnd = useCallback(
    (event: DragEndEvent) => {
      kanbanProps.onDragEnd?.(event)
      if (event.activatorEvent.defaultPrevented) return

      const { active, over } = event
      if (!over) {
        setActiveId(null)
        return
      }

      if (active.id in value && over.id in value) {
        const activeIndex = Object.keys(value).indexOf(active.id as string)
        const overIndex = Object.keys(value).indexOf(over.id as string)
        if (activeIndex !== overIndex) {
          const newOrder = arrayMove(Object.keys(value), activeIndex, overIndex)
          const newColumns: Record<UniqueIdentifier, T[]> = {}
          for (const key of newOrder) {
            const items = value[key]
            if (items) newColumns[key] = items
          }
          if (onMove) {
            onMove({ ...event, activeIndex, overIndex })
          } else {
            onValueChange?.(newColumns)
          }
        }
      } else {
        const activeColumn = getColumn(active.id)
        const overColumn = getColumn(over.id)
        if (!activeColumn || !overColumn) {
          setActiveId(null)
          return
        }

        if (activeColumn === overColumn) {
          const items = value[activeColumn]
          if (!items) {
            setActiveId(null)
            return
          }
          const activeIndex = items.findIndex(
            (item) => getItemValue(item) === active.id
          )
          const overIndex = items.findIndex(
            (item) => getItemValue(item) === over.id
          )
          if (activeIndex !== overIndex) {
            const newColumns = { ...value }
            newColumns[activeColumn] = arrayMove(items, activeIndex, overIndex)
            if (onMove) {
              onMove({ ...event, activeIndex, overIndex })
            } else {
              onValueChange?.(newColumns)
            }
          }
        }
      }

      setActiveId(null)
      hasMovedRef.current = false
    },
    [
      value,
      getColumn,
      getItemValue,
      onValueChange,
      onMove,
      kanbanProps.onDragEnd,
    ]
  )

  const onDragCancel = useCallback(
    (event: DragCancelEvent) => {
      kanbanProps.onDragCancel?.(event)
      if (event.activatorEvent.defaultPrevented) return
      setActiveId(null)
      hasMovedRef.current = false
    },
    [kanbanProps.onDragCancel]
  )

  const announcements: Announcements = useMemo(
    () => ({
      onDragStart({ active }) {
        const isColumn = active.id in value
        const itemType = isColumn ? "column" : "item"
        const position = isColumn
          ? Object.keys(value).indexOf(active.id as string) + 1
          : (() => {
              const col = getColumn(active.id)
              if (!col || !value[col]) return 1
              return (
                value[col].findIndex(
                  (item) => getItemValue(item) === active.id
                ) + 1
              )
            })()
        const total = isColumn
          ? Object.keys(value).length
          : (() => {
              const col = getColumn(active.id)
              return col ? (value[col]?.length ?? 0) : 0
            })()
        return `Picked up ${itemType} at position ${position} of ${total}`
      },
      onDragOver({ active, over }) {
        if (!over) return
        const isColumn = active.id in value
        const itemType = isColumn ? "column" : "item"
        const overCol = getColumn(over.id)
        const activeCol = getColumn(active.id)
        const position = isColumn
          ? Object.keys(value).indexOf(over.id as string) + 1
          : (() => {
              if (!overCol || !value[overCol]) return 1
              return (
                value[overCol].findIndex(
                  (item) => getItemValue(item) === over.id
                ) + 1
              )
            })()
        const total = isColumn
          ? Object.keys(value).length
          : overCol
            ? (value[overCol]?.length ?? 0)
            : 0
        if (isColumn)
          return `${itemType} is now at position ${position} of ${total}`
        if (activeCol !== overCol)
          return `${itemType} is now at position ${position} of ${total} in ${overCol}`
        return `${itemType} is now at position ${position} of ${total}`
      },
      onDragEnd({ active, over }) {
        if (!over) return
        const isColumn = active.id in value
        const itemType = isColumn ? "column" : "item"
        const overCol = getColumn(over.id)
        const activeCol = getColumn(active.id)
        const position = isColumn
          ? Object.keys(value).indexOf(over.id as string) + 1
          : (() => {
              if (!overCol || !value[overCol]) return 1
              return (
                value[overCol].findIndex(
                  (item) => getItemValue(item) === over.id
                ) + 1
              )
            })()
        const total = isColumn
          ? Object.keys(value).length
          : overCol
            ? (value[overCol]?.length ?? 0)
            : 0
        if (isColumn)
          return `${itemType} was dropped at position ${position} of ${total}`
        if (activeCol !== overCol)
          return `${itemType} was dropped at position ${position} of ${total} in ${overCol}`
        return `${itemType} was dropped at position ${position} of ${total}`
      },
      onDragCancel({ active }) {
        const isColumn = active.id in value
        const itemType = isColumn ? "column" : "item"
        return `Dragging was cancelled. ${itemType} was dropped.`
      },
    }),
    [value, getColumn, getItemValue]
  )

  const contextValue = useMemo<KanbanContextValue<T>>(
    () => ({
      id,
      items: value,
      modifiers,
      strategy,
      orientation,
      activeId,
      setActiveId,
      getItemValue,
      flatCursor,
    }),
    [
      id,
      value,
      activeId,
      modifiers,
      strategy,
      orientation,
      getItemValue,
      flatCursor,
    ]
  )

  return (
    <KanbanContext.Provider value={contextValue as KanbanContextValue<unknown>}>
      <DndContext
        collisionDetection={collisionDetection}
        modifiers={modifiers}
        sensors={sensors}
        {...kanbanProps}
        id={id}
        measuring={{ droppable: { strategy: MeasuringStrategy.Always } }}
        onDragStart={onDragStart}
        onDragOver={onDragOver}
        onDragEnd={onDragEnd}
        onDragCancel={onDragCancel}
        accessibility={{
          announcements,
          screenReaderInstructions: {
            draggable: `
              To pick up a kanban item or column, press space or enter.
              While dragging, use the arrow keys to move the item.
              Press space or enter again to drop the item in its new position, or press escape to cancel.
            `,
          },
          ...accessibility,
        }}
      />
    </KanbanContext.Provider>
  )
}

const KanbanBoardContext = createContext<boolean>(false)

type KanbanBoardProps = React.ComponentProps<"div"> & {
  children: React.ReactNode
  asChild?: boolean
}

function KanbanBoard({
  asChild,
  className,
  ref,
  ...boardProps
}: KanbanBoardProps) {
  const context = useKanbanContext(BOARD_NAME)
  const columns = useMemo(() => Object.keys(context.items), [context.items])
  const BoardPrimitive = asChild ? Slot : "div"

  return (
    <KanbanBoardContext.Provider value={true}>
      <SortableContext
        items={columns}
        strategy={
          context.orientation === "horizontal"
            ? horizontalListSortingStrategy
            : verticalListSortingStrategy
        }
      >
        <BoardPrimitive
          aria-orientation={context.orientation}
          data-orientation={context.orientation}
          data-slot="kanban-board"
          {...boardProps}
          ref={ref}
          className={cn(
            "flex size-full gap-4",
            context.orientation === "horizontal" ? "flex-row" : "flex-col",
            className
          )}
        />
      </SortableContext>
    </KanbanBoardContext.Provider>
  )
}

type KanbanColumnContextValue = {
  id: string
  attributes: DraggableAttributes
  listeners: DraggableSyntheticListeners | undefined
  setActivatorNodeRef: (node: HTMLElement | null) => void
  isDragging?: boolean
  disabled?: boolean
}

const KanbanColumnContext = createContext<KanbanColumnContextValue | null>(null)

function useKanbanColumnContext(consumerName: string) {
  const context = useContext(KanbanColumnContext)
  if (!context) {
    throw new Error(
      `\`${consumerName}\` must be used within \`${COLUMN_NAME}\``
    )
  }
  return context
}

const animateLayoutChanges: AnimateLayoutChanges = (args) =>
  defaultAnimateLayoutChanges({ ...args, wasDragging: true })

type KanbanColumnProps = React.ComponentProps<"div"> & {
  value: UniqueIdentifier
  children: React.ReactNode
  asChild?: boolean
  asHandle?: boolean
  disabled?: boolean
}

function KanbanColumn({
  value,
  asChild,
  asHandle,
  disabled,
  className,
  style,
  ref,
  ...columnProps
}: KanbanColumnProps) {
  const id = useId()
  const context = useKanbanContext(COLUMN_NAME)
  const inBoard = useContext(KanbanBoardContext)
  const inOverlay = useContext(KanbanOverlayContext)

  if (!inBoard && !inOverlay) {
    throw new Error(
      `\`${COLUMN_NAME}\` must be used within \`${BOARD_NAME}\` or \`${OVERLAY_NAME}\``
    )
  }

  if (value === "")
    throw new Error(`\`${COLUMN_NAME}\` value cannot be an empty string`)

  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: value, disabled, animateLayoutChanges })

  const composedRef = useComposedRefs(ref, (node: HTMLDivElement | null) => {
    if (disabled) return
    setNodeRef(node)
  })

  const composedStyle = useMemo<React.CSSProperties>(
    () => ({
      transform: CSS.Transform.toString(transform),
      transition,
      ...style,
    }),
    [transform, transition, style]
  )

  const items = useMemo(() => {
    const colItems = context.items[value] ?? []
    return colItems.map((item) => context.getItemValue(item))
  }, [context.items, value, context.getItemValue])

  const columnContext = useMemo<KanbanColumnContextValue>(
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

  const ColumnPrimitive = asChild ? Slot : "div"

  return (
    <KanbanColumnContext.Provider value={columnContext}>
      <SortableContext
        items={items}
        strategy={
          context.orientation === "horizontal"
            ? horizontalListSortingStrategy
            : verticalListSortingStrategy
        }
      >
        <ColumnPrimitive
          id={id}
          data-disabled={disabled}
          data-dragging={isDragging ? "" : undefined}
          data-slot="kanban-column"
          {...columnProps}
          {...(asHandle && !disabled ? attributes : {})}
          {...(asHandle && !disabled ? listeners : {})}
          ref={composedRef}
          style={composedStyle}
          className={cn(
            "flex size-full flex-col gap-2 rounded-lg border bg-muted p-2.5 aria-disabled:pointer-events-none aria-disabled:opacity-50",
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
      </SortableContext>
    </KanbanColumnContext.Provider>
  )
}

type KanbanColumnHandleProps = React.ComponentProps<"button"> & {
  asChild?: boolean
}

function KanbanColumnHandle({
  asChild,
  disabled,
  className,
  ref,
  ...props
}: KanbanColumnHandleProps) {
  const context = useKanbanContext(COLUMN_HANDLE_NAME)
  const columnContext = useKanbanColumnContext(COLUMN_HANDLE_NAME)
  const isDisabled = disabled ?? columnContext.disabled
  const composedRef = useComposedRefs(ref, (node: HTMLButtonElement | null) => {
    if (isDisabled) return
    columnContext.setActivatorNodeRef(node)
  })
  const HandlePrimitive = asChild ? Slot : "button"

  return (
    <HandlePrimitive
      type="button"
      aria-controls={columnContext.id}
      data-disabled={isDisabled}
      data-dragging={columnContext.isDragging ? "" : undefined}
      data-slot="kanban-column-handle"
      {...props}
      {...(isDisabled ? {} : columnContext.attributes)}
      {...(isDisabled ? {} : columnContext.listeners)}
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
}

type KanbanItemContextValue = {
  id: string
  attributes: DraggableAttributes
  listeners: DraggableSyntheticListeners | undefined
  setActivatorNodeRef: (node: HTMLElement | null) => void
  isDragging?: boolean
  disabled?: boolean
}

const KanbanItemContext = createContext<KanbanItemContextValue | null>(null)

function useKanbanItemContext(consumerName: string) {
  const context = useContext(KanbanItemContext)
  if (!context) {
    throw new Error(`\`${consumerName}\` must be used within \`${ITEM_NAME}\``)
  }
  return context
}

type KanbanItemProps = React.ComponentProps<"div"> & {
  value: UniqueIdentifier
  asHandle?: boolean
  asChild?: boolean
  disabled?: boolean
}

function KanbanItem({
  value,
  style,
  asHandle,
  asChild,
  disabled,
  className,
  ref,
  ...itemProps
}: KanbanItemProps) {
  const id = useId()
  const context = useKanbanContext(ITEM_NAME)
  const inBoard = useContext(KanbanBoardContext)
  const inOverlay = useContext(KanbanOverlayContext)

  if (!inBoard && !inOverlay) {
    throw new Error(`\`${ITEM_NAME}\` must be used within \`${BOARD_NAME}\``)
  }

  if (value === "")
    throw new Error(`\`${ITEM_NAME}\` value cannot be an empty string`)

  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: value, disabled })

  const composedRef = useComposedRefs(ref, (node: HTMLDivElement | null) => {
    if (disabled) return
    setNodeRef(node)
  })

  const composedStyle = useMemo<React.CSSProperties>(
    () => ({
      transform: CSS.Transform.toString(transform),
      transition,
      ...style,
    }),
    [transform, transition, style]
  )

  const itemContext = useMemo<KanbanItemContextValue>(
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
    <KanbanItemContext.Provider value={itemContext}>
      <ItemPrimitive
        id={id}
        data-disabled={disabled}
        data-dragging={isDragging ? "" : undefined}
        data-slot="kanban-item"
        {...itemProps}
        {...(asHandle && !disabled ? attributes : {})}
        {...(asHandle && !disabled ? listeners : {})}
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
    </KanbanItemContext.Provider>
  )
}

type KanbanItemHandleProps = React.ComponentProps<"button"> & {
  asChild?: boolean
}

function KanbanItemHandle({
  asChild,
  disabled,
  className,
  ref,
  ...props
}: KanbanItemHandleProps) {
  const context = useKanbanContext(ITEM_HANDLE_NAME)
  const itemContext = useKanbanItemContext(ITEM_HANDLE_NAME)
  const isDisabled = disabled ?? itemContext.disabled
  const composedRef = useComposedRefs(ref, (node: HTMLButtonElement | null) => {
    if (isDisabled) return
    itemContext.setActivatorNodeRef(node)
  })
  const HandlePrimitive = asChild ? Slot : "button"

  return (
    <HandlePrimitive
      type="button"
      aria-controls={itemContext.id}
      data-disabled={isDisabled}
      data-dragging={itemContext.isDragging ? "" : undefined}
      data-slot="kanban-item-handle"
      {...props}
      {...(isDisabled ? {} : itemContext.attributes)}
      {...(isDisabled ? {} : itemContext.listeners)}
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
}

const KanbanOverlayContext = createContext(false)

const dropAnimation: DropAnimation = {
  sideEffects: defaultDropAnimationSideEffects({
    styles: { active: { opacity: "0.4" } },
  }),
}

type KanbanOverlayProps = Omit<
  React.ComponentProps<typeof DragOverlay>,
  "children"
> & {
  container?: Element | DocumentFragment | null
  children?:
    | React.ReactNode
    | ((params: {
        value: UniqueIdentifier
        variant: "column" | "item"
      }) => React.ReactNode)
}

function KanbanOverlay({
  container: containerProp,
  children,
  ...overlayProps
}: KanbanOverlayProps) {
  const context = useKanbanContext(OVERLAY_NAME)
  const [mounted, setMounted] = useState(false)
  useLayoutEffect(() => setMounted(true), [])

  const container =
    containerProp ?? (mounted ? globalThis.document?.body : null)
  if (!container) return null

  const variant =
    context.activeId && context.activeId in context.items ? "column" : "item"

  return ReactDOM.createPortal(
    <DragOverlay
      dropAnimation={dropAnimation}
      modifiers={context.modifiers}
      className={cn(!context.flatCursor && "cursor-grabbing")}
      {...overlayProps}
    >
      <KanbanOverlayContext.Provider value={true}>
        {context.activeId && children
          ? typeof children === "function"
            ? children({ value: context.activeId, variant })
            : children
          : null}
      </KanbanOverlayContext.Provider>
    </DragOverlay>,
    container
  )
}

export {
  KanbanRoot as Kanban,
  KanbanBoard,
  KanbanColumn,
  KanbanColumnHandle,
  KanbanItem,
  KanbanItemHandle,
  KanbanOverlay,
  KanbanRoot as Root,
  KanbanBoard as Board,
  KanbanColumn as Column,
  KanbanColumnHandle as ColumnHandle,
  KanbanItem as Item,
  KanbanItemHandle as ItemHandle,
  KanbanOverlay as Overlay,
}
