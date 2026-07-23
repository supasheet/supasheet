import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { formatDistanceToNow } from "date-fns"
import { PencilIcon, SendIcon, Trash2Icon, XIcon } from "lucide-react"

import { Avatar, AvatarFallback, AvatarImage } from "#/components/ui/avatar"
import { Button } from "#/components/ui/button"
import { Textarea } from "#/components/ui/textarea"
import {
  Timeline,
  TimelineContent,
  TimelineDate,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
  TimelineTitle,
} from "#/components/ui/timeline"
import { useAuthUser } from "#/hooks/use-user"
import type { ResourceComment } from "#/lib/supabase/data/resource"
import {
  deleteCommentMutationOptions,
  insertCommentMutationOptions,
  resourceCommentsQueryOptions,
  updateCommentMutationOptions,
} from "#/lib/supabase/data/resource"

function userInitials(name: string | null) {
  if (!name) return "?"
  return name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2)
}

function CommentTimelineItem({
  comment,
  step,
  isOwner,
  onEdit,
  onDelete,
}: {
  comment: ResourceComment
  step: number
  isOwner: boolean
  onEdit: (comment: ResourceComment) => void
  onDelete: (id: string) => void
}) {
  return (
    <TimelineItem step={step}>
      <TimelineIndicator className={isOwner ? "border-primary" : ""} />
      <TimelineSeparator />
      <TimelineContent>
        <div className="rounded-lg border bg-card p-3">
          <div className="flex items-start justify-between gap-2">
            <div className="flex items-center gap-2">
              <Avatar className="h-5 w-5 shrink-0">
                <AvatarImage
                  src={comment.created_by_picture_url ?? undefined}
                />
                <AvatarFallback className="text-[10px]">
                  {userInitials(comment.created_by_name)}
                </AvatarFallback>
              </Avatar>
              <TimelineTitle className="text-sm">
                {comment.created_by_name ?? "Unknown"}
              </TimelineTitle>
              <TimelineDate
                dateTime={comment.created_at}
                className="mb-0 inline text-xs"
              >
                {formatDistanceToNow(new Date(comment.created_at), {
                  addSuffix: true,
                })}
                {comment.updated_at !== comment.created_at && (
                  <span className="ml-1 text-muted-foreground/50">
                    · edited
                  </span>
                )}
              </TimelineDate>
            </div>
            {isOwner && (
              <div className="flex shrink-0 gap-0.5">
                <Button
                  size="icon-xs"
                  variant="ghost"
                  className="text-muted-foreground"
                  onClick={() => onEdit(comment)}
                >
                  <PencilIcon />
                </Button>
                <Button
                  size="icon-xs"
                  variant="ghost"
                  className="text-muted-foreground hover:text-destructive"
                  onClick={() => onDelete(comment.id)}
                >
                  <Trash2Icon />
                </Button>
              </div>
            )}
          </div>
          <p className="mt-2 whitespace-pre-wrap wrap-break-word text-sm text-muted-foreground">
            {comment.content}
          </p>
        </div>
      </TimelineContent>
    </TimelineItem>
  )
}

function EditCommentForm({
  comment,
  step,
  onSave,
  onCancel,
  isPending,
}: {
  comment: ResourceComment
  step: number
  onSave: (id: string, content: string) => void
  onCancel: () => void
  isPending: boolean
}) {
  const [value, setValue] = useState(comment.content)

  return (
    <TimelineItem step={step}>
      <TimelineIndicator className="border-primary" />
      <TimelineSeparator />
      <TimelineContent>
        <div className="rounded-lg border bg-card p-3">
          <div className="mb-2 flex items-center gap-2">
            <Avatar className="h-5 w-5 shrink-0">
              <AvatarImage src={comment.created_by_picture_url ?? undefined} />
              <AvatarFallback className="text-[10px]">
                {userInitials(comment.created_by_name)}
              </AvatarFallback>
            </Avatar>
            <TimelineTitle className="text-sm">
              {comment.created_by_name ?? "Unknown"}
            </TimelineTitle>
            <Button
              size="icon-xs"
              variant="ghost"
              className="ml-auto text-muted-foreground"
              onClick={onCancel}
            >
              <XIcon />
            </Button>
          </div>
          <div className="flex flex-col gap-2">
            <Textarea
              value={value}
              onChange={(e) => setValue(e.target.value)}
              rows={3}
              className="text-sm"
              autoFocus
            />
            <div className="flex gap-2">
              <Button
                size="sm"
                onClick={() => onSave(comment.id, value)}
                disabled={isPending || !value.trim()}
              >
                Save
              </Button>
            </div>
          </div>
        </div>
      </TimelineContent>
    </TimelineItem>
  )
}

export function ResourceComments({
  schema,
  resource,
  recordId,
  comments,
}: {
  schema: string
  resource: string
  recordId: string
  comments: ResourceComment[]
}) {
  const authUser = useAuthUser()
  const queryClient = useQueryClient()
  const [newContent, setNewContent] = useState("")
  const [editingComment, setEditingComment] = useState<ResourceComment | null>(
    null
  )

  const invalidate = () =>
    queryClient.invalidateQueries({
      queryKey: resourceCommentsQueryOptions(schema, resource, recordId)
        .queryKey,
    })

  const insertMutation = useMutation({
    ...insertCommentMutationOptions(),
    onSuccess: () => {
      setNewContent("")
      invalidate()
    },
  })

  const updateMutation = useMutation({
    ...updateCommentMutationOptions(),
    onSuccess: () => {
      setEditingComment(null)
      invalidate()
    },
  })

  const deleteMutation = useMutation({
    ...deleteCommentMutationOptions(),
    onSuccess: invalidate,
  })

  const handleSubmit = () => {
    if (!newContent.trim() || !authUser) return
    insertMutation.mutate({
      schema_name: schema,
      table_name: resource,
      record_id: recordId,
      content: newContent.trim(),
      created_by: authUser.id,
    })
  }

  return (
    <Timeline className="px-1 py-2">
      {comments.length === 0 && (
        <TimelineItem step={1}>
          <TimelineIndicator className="border-muted-foreground/30" />
          <TimelineSeparator />
          <TimelineContent>
            <div className="flex flex-col items-center justify-center py-6 text-center">
              <p className="text-sm font-medium">No comments yet</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Be the first to leave a comment on this record.
              </p>
            </div>
          </TimelineContent>
        </TimelineItem>
      )}
      {comments.map((comment, index) =>
        editingComment?.id === comment.id ? (
          <EditCommentForm
            key={comment.id}
            comment={comment}
            step={index + 1}
            onSave={(id, content) => updateMutation.mutate({ id, content })}
            onCancel={() => setEditingComment(null)}
            isPending={updateMutation.isPending}
          />
        ) : (
          <CommentTimelineItem
            key={comment.id}
            comment={comment}
            step={index + 1}
            isOwner={comment.created_by === authUser?.id}
            onEdit={setEditingComment}
            onDelete={(id) => deleteMutation.mutate(id)}
          />
        )
      )}

      <TimelineItem step={comments.length + 1}>
        <TimelineIndicator className="border-muted-foreground/30" />
        <TimelineContent>
          <NewCommentForm
            value={newContent}
            onChange={setNewContent}
            onSubmit={handleSubmit}
            isPending={insertMutation.isPending}
            authUser={authUser}
          />
        </TimelineContent>
      </TimelineItem>
    </Timeline>
  )
}

function NewCommentForm({
  value,
  onChange,
  onSubmit,
  isPending,
  authUser,
}: {
  value: string
  onChange: (v: string) => void
  onSubmit: () => void
  isPending: boolean
  authUser: { id: string } | null | undefined
}) {
  return (
    <div className="flex flex-col gap-2">
      <Textarea
        placeholder="Write a comment… (Ctrl+Enter to post)"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        rows={3}
        className="text-sm"
        onKeyDown={(e) => {
          if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
            e.preventDefault()
            onSubmit()
          }
        }}
      />
      <div className="flex justify-end">
        <Button
          size="sm"
          onClick={onSubmit}
          disabled={isPending || !value.trim() || !authUser}
        >
          <SendIcon className="mr-1.5 h-3.5 w-3.5" />
          {isPending ? "Posting…" : "Post comment"}
        </Button>
      </div>
    </div>
  )
}
