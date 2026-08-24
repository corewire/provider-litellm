/*
Copyright 2024 Corewire.
*/

package controller

import (
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/crossplane/upjet/v2/pkg/controller"

	credential "github.com/corewire/provider-litellm/internal/controller/litellm/credential"
	key "github.com/corewire/provider-litellm/internal/controller/litellm/key"
	model "github.com/corewire/provider-litellm/internal/controller/litellm/model"
	organization "github.com/corewire/provider-litellm/internal/controller/litellm/organization"
	team "github.com/corewire/provider-litellm/internal/controller/litellm/team"
	server "github.com/corewire/provider-litellm/internal/controller/mcp/server"
	member "github.com/corewire/provider-litellm/internal/controller/organization/member"
	memberadd "github.com/corewire/provider-litellm/internal/controller/organization/memberadd"
	providerconfig "github.com/corewire/provider-litellm/internal/controller/providerconfig"
	memberteam "github.com/corewire/provider-litellm/internal/controller/team/member"
	memberaddteam "github.com/corewire/provider-litellm/internal/controller/team/memberadd"
	store "github.com/corewire/provider-litellm/internal/controller/vector/store"
)

// Setup creates all controllers with the supplied logger and adds them to
// the supplied manager.
func Setup(mgr ctrl.Manager, o controller.Options) error {
	for _, setup := range []func(ctrl.Manager, controller.Options) error{
		credential.Setup,
		key.Setup,
		model.Setup,
		organization.Setup,
		team.Setup,
		server.Setup,
		member.Setup,
		memberadd.Setup,
		providerconfig.Setup,
		memberteam.Setup,
		memberaddteam.Setup,
		store.Setup,
	} {
		if err := setup(mgr, o); err != nil {
			return err
		}
	}
	return nil
}

// SetupGated creates all controllers with the supplied logger and adds them to
// the supplied manager gated.
func SetupGated(mgr ctrl.Manager, o controller.Options) error {
	for _, setup := range []func(ctrl.Manager, controller.Options) error{
		credential.SetupGated,
		key.SetupGated,
		model.SetupGated,
		organization.SetupGated,
		team.SetupGated,
		server.SetupGated,
		member.SetupGated,
		memberadd.SetupGated,
		providerconfig.SetupGated,
		memberteam.SetupGated,
		memberaddteam.SetupGated,
		store.SetupGated,
	} {
		if err := setup(mgr, o); err != nil {
			return err
		}
	}
	return nil
}

// SetupWebhookWithManager registers conversion webhooks for all resource kinds in the group.
func SetupWebhookWithManager(mgr ctrl.Manager) error {
	for _, setup := range []func(ctrl.Manager) error{
		credential.SetupWebhookWithManager,
		key.SetupWebhookWithManager,
		model.SetupWebhookWithManager,
		organization.SetupWebhookWithManager,
		team.SetupWebhookWithManager,
		server.SetupWebhookWithManager,
		member.SetupWebhookWithManager,
		memberadd.SetupWebhookWithManager,
		providerconfig.SetupWebhookWithManager,
		memberteam.SetupWebhookWithManager,
		memberaddteam.SetupWebhookWithManager,
		store.SetupWebhookWithManager,
	} {
		if err := setup(mgr); err != nil {
			return err
		}
	}
	return nil
}
