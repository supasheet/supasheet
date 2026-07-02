import { useMutation, useQueryClient } from "@tanstack/react-query"

import { useForm } from "@tanstack/react-form"
import { useRouter } from "@tanstack/react-router"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Input } from "#/components/ui/input"
import { Label } from "#/components/ui/label"
import { useAuthUser, useUser } from "#/hooks/use-user"
import { updateAccountNameMutationOptions } from "#/lib/supabase/data/users"

export function ProfileNameCard() {
  const user = useUser()
  const authUser = useAuthUser()
  const queryClient = useQueryClient()
  const router = useRouter()

  const { mutateAsync: saveName } = useMutation({
    ...updateAccountNameMutationOptions(authUser!.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({
        queryKey: ["supasheet", "user", authUser!.id],
      })
      await router.invalidate()
      toast.success("Name updated")
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Failed to update name")
    },
  })

  const form = useForm({
    defaultValues: { name: user?.name ?? "" },
    onSubmit: async ({ value }) => {
      await saveName(value.name.trim())
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Full name</CardTitle>
        <CardDescription>
          This is the name displayed across your account.
        </CardDescription>
      </CardHeader>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          form.handleSubmit()
        }}
      >
        <CardContent className="py-4">
          <form.Field
            name="name"
            validators={{
              onChange: ({ value }) => {
                if (!value.trim()) return "Name is required"
                if (value.trim().length < 2)
                  return "Name must be at least 2 characters"
                if (value.trim().length > 255)
                  return "Name must be 255 characters or fewer"
                return undefined
              },
            }}
          >
            {(field) => (
              <div className="space-y-1.5">
                <Label htmlFor={field.name}>Name</Label>
                <Input
                  id={field.name}
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="Your name"
                  aria-invalid={field.state.meta.errors.length > 0}
                />
                {field.state.meta.errors.length > 0 && (
                  <p className="text-xs text-destructive">
                    {String(field.state.meta.errors[0])}
                  </p>
                )}
              </div>
            )}
          </form.Field>
        </CardContent>
        <CardFooter className="justify-end">
          <form.Subscribe
            selector={(s) => ({
              isSubmitting: s.isSubmitting,
              isDirty: s.isDirty,
              canSubmit: s.canSubmit,
            })}
          >
            {({ isSubmitting, isDirty, canSubmit }) => (
              <Button
                type="submit"
                size="sm"
                disabled={!isDirty || !canSubmit || isSubmitting}
              >
                {isSubmitting ? "Saving…" : "Save name"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
