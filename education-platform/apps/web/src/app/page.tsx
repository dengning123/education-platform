import { redirect } from "next/navigation";

import { getVerifiedUser } from "@/lib/auth/verified-user";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const user = await getVerifiedUser();
  redirect(user ? "/account" : "/sign-in");
}
