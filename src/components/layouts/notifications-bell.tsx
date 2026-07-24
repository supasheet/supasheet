import { Suspense, useState } from "react"

import { useQuery } from "@tanstack/react-query"

import { BellIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "#/components/ui/sheet"
import { useIsMobile } from "#/hooks/use-mobile"
import { unreadNotificationsCountQueryOptions } from "#/lib/supabase/data/core"
import { cn } from "#/lib/utils"

import {
  MarkAllReadButton,
  NotificationsList,
  NotificationsListSkeleton,
} from "./notification-list"

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
