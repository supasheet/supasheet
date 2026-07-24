import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import {
  Timeline,
  TimelineContent,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
} from "#/components/ui/timeline"
import { useAuthUser } from "#/hooks/use-user"
import type { ResourceComment } from "#/lib/supabase/data/resource"
import {
  deleteCommentMutationOptions,
  insertCommentMutationOptions,
  resourceCommentsQueryOptions,
  updateCommentMutationOptions,
} from "#/lib/supabase/data/resource"

import {
  CommentTimelineItem,
  EditCommentForm,
  NewCommentForm,
} from "./comment-item"

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
