import { createFileRoute } from "@tanstack/react-router"

import { ProfileAvatarCard } from "#/components/account/profile-avatar-card"
import { ProfileNameCard } from "#/components/account/profile-name-card"
import { DefaultHeader } from "#/components/layouts/default-header"
import { PageContainer } from "#/components/layouts/page-container"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/account/profile")({
  head: () => ({ meta: [{ title: pageTitle("Profile") }] }),
  component: ProfilePage,
})

function ProfilePage() {
  return (
    <div>
      <DefaultHeader
        breadcrumbs={[{ title: "Profile", url: "/account/profile" }]}
      />
      <PageContainer size="narrow">
        <ProfileAvatarCard />
        <ProfileNameCard />
      </PageContainer>
    </div>
  )
}
