import type { Metadata } from "next";
import { ProfileForm } from "@/components/profile/ProfileForm";

export const metadata: Metadata = { title: "Your profile" };

export default function ProfilePage() {
  return <ProfileForm />;
}
