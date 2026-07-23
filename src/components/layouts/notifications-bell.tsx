import { Suspense, useState } from "react"

import { useRouter } from "@tanstack/react-router"

import {
  useMutation,
  useQuery,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query"

import { formatDistanceToNow } from "date-fns"
import {
  ArchiveIcon,
  BellIcon,
  CheckCheckIcon,
  CheckIcon,
  Trash2Icon,
} from "lucide-react"
import { toast } from "sonner"

import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "#/components/ui/sheet"
import { Skeleton } from "#/components/ui/skeleton"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import { useIsMobile } from "#/hooks/use-mobile"
import type { UserNotificationRow } from "#/lib/supabase/data/core"
import {
  archiveNotificationMutationOptions,
  deleteNotificationMutationOptions,
  markAllNotificationsReadMutationOptions,
  markNotificationReadMutationOptions,
  notificationsQueryOptions,
  unreadNotificationsCountQueryOptions,
} from "#/lib/supabase/data/core"
import { cn } from "#/lib/utils"

const NOTIFICATIONS_KEY = ["supasheet", "notifications"]

export function NotificationsBell({ className }: { className?: string }) {
  const [open, setOpen] = useState(false)
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  const { data: unreadCount = 0 } = useQuery(
    unreadNotificationsCountQueryOptions
  )

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={
              unreadCount > 0
                ? `Notifications (${unreadCount} unread)`
                : "Notifications"
            }
            className={cn("relative", className)}
          />
        }
      >
        <BellIcon className="size-4" />
        {unreadCount > 0 && (
          <span className="absolute top-0.5 right-0.5 flex size-3.5 items-center justify-center rounded-full bg-primary text-[9px] font-medium text-primary-foreground">
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        )}
      </SheetTrigger>

      <SheetContent
        side={side}
        className={cn(
          "gap-0 p-0",
          side === "right" && "w-full! sm:max-w-md!",
          side === "bottom" && "max-h-[80vh]"
        )}
      >
        <SheetHeader className="flex-row items-center justify-between border-b">
          <SheetTitle>Notifications</SheetTitle>
          <MarkAllReadButton unreadCount={unreadCount} />
        </SheetHeader>
        <Suspense fallback={<NotificationsListSkeleton />}>
          <NotificationsList onNavigate={() => setOpen(false)} />
        </Suspense>
      </SheetContent>
    </Sheet>
  )
}

function MarkAllReadButton({ unreadCount }: { unreadCount: number }) {
  const queryClient = useQueryClient()
  const markAllRead = useMutation({
    ...markAllNotificationsReadMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: NOTIFICATIONS_KEY })
      toast.success("All notifications marked as read")
    },
    onError: (e) =>
      toast.error(
        e instanceof Error ? e.message : "Failed to mark notifications as read"
      ),
  })

  return (
    <Button
      variant="outline"
      size="sm"
      className="mr-10"
      disabled={unreadCount === 0 || markAllRead.isPending}
      onClick={() => markAllRead.mutate()}
    >
      <CheckCheckIcon />
      Mark all read
    </Button>
  )
}

function NotificationsListSkeleton() {
  return (
    <div className="flex flex-1 flex-col gap-2 overflow-y-auto p-4">
      {Array.from({ length: 4 }).map((_, i) => (
        <Skeleton key={i} className="h-20 w-full rounded-lg" />
      ))}
    </div>
  )
}

function NotificationsList({ onNavigate }: { onNavigate: () => void }) {
  const queryClient = useQueryClient()
  const router = useRouter()
  const { data: notifications } = useSuspenseQuery(notificationsQueryOptions)

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: NOTIFICATIONS_KEY })

  const markRead = useMutation({
    ...markNotificationReadMutationOptions,
    onSuccess: invalidate,
    onError: (e) =>
      toast.error(
        e instanceof Error ? e.message : "Failed to mark notification as read"
      ),
  })
  const archive = useMutation({
    ...archiveNotificationMutationOptions,
    onSuccess: invalidate,
    onError: (e) =>
      toast.error(
        e instanceof Error ? e.message : "Failed to archive notification"
      ),
  })
  const remove = useMutation({
    ...deleteNotificationMutationOptions,
    onSuccess: invalidate,
    onError: (e) =>
      toast.error(
        e instanceof Error ? e.message : "Failed to delete notification"
      ),
  })
  const deleteConfirm = useConfirmAction((id: string) => {
    remove.mutate(id)
  })

  if (notifications.length === 0) {
    return (
      <div className="flex flex-1 flex-col p-4">
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <BellIcon />
            </EmptyMedia>
            <EmptyTitle>You're all caught up</EmptyTitle>
            <EmptyDescription>
              New notifications will appear here.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      </div>
    )
  }

  return (
    <>
      <ul className="flex flex-1 flex-col gap-2 overflow-y-auto p-4">
        {notifications.map((item) => (
          <NotificationItem
            key={item.id}
            item={item}
            onOpen={() => {
              if (!item.notification.link) return
              if (!item.read_at) markRead.mutate(item.id)
              router.history.push(item.notification.link)
              onNavigate()
            }}
            onMarkRead={() => markRead.mutate(item.id)}
            onArchive={() => archive.mutate(item.id)}
            onDelete={() => deleteConfirm.request(item.id)}
          />
        ))}
      </ul>
      <ConfirmDeleteDialog
        open={deleteConfirm.open}
        onOpenChange={(open) => !open && deleteConfirm.cancel()}
        onConfirm={deleteConfirm.confirm}
        title="Delete notification?"
        pending={deleteConfirm.pending}
      />
    </>
  )
}

function NotificationItem({
  item,
  onOpen,
  onMarkRead,
  onArchive,
  onDelete,
}: {
  item: UserNotificationRow
  onOpen: () => void
  onMarkRead: () => void
  onArchive: () => void
  onDelete: () => void
}) {
  const isUnread = !item.read_at
  const { notification } = item
  const hasLink = !!notification.link

  return (
    <li
      className={
        "group flex items-start gap-3 rounded-lg border p-3 transition-colors " +
        (isUnread ? "bg-muted/40" : "bg-background") +
        (hasLink ? " hover:bg-muted/60" : "")
      }
    >
      <button
        type="button"
        onClick={onOpen}
        disabled={!hasLink}
        className="flex flex-1 items-start gap-3 text-left disabled:cursor-default"
      >
        <div className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-md border bg-background text-muted-foreground">
          <BellIcon className="size-4" />
        </div>

        <div className="flex flex-1 flex-col gap-1">
          <div className="flex items-center gap-2">
            <p className="text-sm font-medium">{notification.title}</p>
            {isUnread && (
              <span
                aria-label="Unread"
                className="size-1.5 rounded-full bg-primary"
              />
            )}
          </div>
          <Badge variant="outline" className="font-mono text-[10px]">
            {notification.type}
          </Badge>
          {notification.body && (
            <p className="text-sm text-muted-foreground">{notification.body}</p>
          )}
          <p className="text-xs text-muted-foreground">
            {formatDistanceToNow(new Date(notification.created_at), {
              addSuffix: true,
            })}
          </p>
        </div>
      </button>

      <div className="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
        {isUnread && (
          <Button
            size="icon-sm"
            variant="ghost"
            aria-label="Mark as read"
            onClick={onMarkRead}
          >
            <CheckIcon />
          </Button>
        )}
        <Button
          size="icon-sm"
          variant="ghost"
          aria-label="Archive"
          onClick={onArchive}
        >
          <ArchiveIcon />
        </Button>
        <Button
          size="icon-sm"
          variant="ghost"
          aria-label="Delete"
          onClick={onDelete}
        >
          <Trash2Icon />
        </Button>
      </div>
    </li>
  )
}
