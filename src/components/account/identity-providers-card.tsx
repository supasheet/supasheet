import type { Provider } from "@supabase/supabase-js"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { Link2Icon, Link2OffIcon } from "lucide-react"
import { toast } from "sonner"

import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  identitiesQueryOptions,
  linkIdentityMutationOptions,
  unlinkIdentityMutationOptions,
} from "#/lib/supabase/data/identities"

const SUPPORTED_PROVIDERS: {
  provider: Provider
  label: string
  description: string
}[] = [
  {
    provider: "google",
    label: "Google",
    description: "Sign in with your Google account",
  },
  {
    provider: "github",
    label: "GitHub",
    description: "Sign in with your GitHub account",
  },
]

const GoogleIcon = () => (
  <svg
    role="img"
    viewBox="0 0 24 24"
    className="size-5"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path
      d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z"
      fill="currentColor"
    />
  </svg>
)

const GitHubIcon = () => (
  <svg
    role="img"
    viewBox="0 0 24 24"
    className="size-5"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path
      d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"
      fill="currentColor"
    />
  </svg>
)

const PROVIDER_ICONS: Record<string, React.FC> = {
  google: GoogleIcon,
  github: GitHubIcon,
}

export function IdentityProvidersCard() {
  const queryClient = useQueryClient()
  const { data: identities = [], isLoading } = useQuery(identitiesQueryOptions)

  const linkedMap = new Map(identities.map((i) => [i.provider, i]))
  const canUnlink = identities.length > 1

  const {
    mutate: linkIdentity,
    isPending: isLinking,
    variables: linkingProvider,
  } = useMutation({
    ...linkIdentityMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["auth", "identities"] })
      toast.success("Identity linked")
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to link identity"
      )
    },
  })

  const {
    mutate: unlinkIdentity,
    isPending: isUnlinking,
    variables: unlinkingIdentity,
  } = useMutation({
    ...unlinkIdentityMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["auth", "identities"] })
      toast.success("Identity unlinked")
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to unlink identity"
      )
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Linked identities</CardTitle>
        <CardDescription>
          Connect social providers to your account for easier sign-in.
        </CardDescription>
      </CardHeader>
      <CardContent className="divide-y p-0">
        {isLoading ? (
          <div className="px-6 py-4 text-sm text-muted-foreground">
            Loading…
          </div>
        ) : (
          SUPPORTED_PROVIDERS.map(({ provider, label, description }) => {
            const identity = linkedMap.get(provider)
            const Icon = PROVIDER_ICONS[provider]
            const isLinked = !!identity
            const email = isLinked
              ? (identity.identity_data?.email as string | undefined)
              : undefined
            const isActionPending =
              (isLinking && linkingProvider === provider) ||
              (isUnlinking && unlinkingIdentity.id === identity?.id)

            return (
              <div
                key={provider}
                className="flex items-center justify-between px-6 py-4"
              >
                <div className="flex items-center gap-3">
                  <div className="flex size-9 shrink-0 items-center justify-center rounded-md border text-foreground/80">
                    <Icon />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium">{label}</p>
                      {isLinked && (
                        <Badge variant="secondary" className="text-xs">
                          Connected
                        </Badge>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {email ?? description}
                    </p>
                  </div>
                </div>
                {isLinked ? (
                  <Button
                    size="sm"
                    variant="outline"
                    className="text-destructive hover:text-destructive"
                    disabled={!canUnlink || isActionPending}
                    title={
                      canUnlink ? undefined : "Cannot unlink the only identity"
                    }
                    onClick={() => unlinkIdentity(identity)}
                  >
                    <Link2OffIcon className="size-3.5" />
                    {isActionPending ? "Unlinking…" : "Unlink"}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={isActionPending}
                    onClick={() => linkIdentity(provider)}
                  >
                    <Link2Icon className="size-3.5" />
                    {isActionPending ? "Linking…" : "Link"}
                  </Button>
                )}
              </div>
            )
          })
        )}
      </CardContent>
    </Card>
  )
}
