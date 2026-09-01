/*
Copyright 2024 Corewire.
*/

package controller

import (
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/crossplane/upjet/v2/pkg/controller"

	credential "github.com/corewire/provider-litellm/internal/controller/litellm/credential"
	key "github.com/corewire/provider-litellm/internal/controller/litellm/key"
	mcpserver "github.com/corewire/provider-litellm/internal/controller/litellm/mcpserver"
	model "github.com/corewire/provider-litellm/internal/controller/litellm/model"
	organization "github.com/corewire/provider-litellm/internal/controller/litellm/organization"
	organizationmember "github.com/corewire/provider-litellm/internal/controller/litellm/organizationmember"
	organizationmemberadd "github.com/corewire/provider-litellm/internal/controller/litellm/organizationmemberadd"
	team "github.com/corewire/provider-litellm/internal/controller/litellm/team"
	teammember "github.com/corewire/provider-litellm/internal/controller/litellm/teammember"
	teammemberadd "github.com/corewire/provider-litellm/internal/controller/litellm/teammemberadd"
	vectorstore "github.com/corewire/provider-litellm/internal/controller/litellm/vectorstore"
	providerconfig "github.com/corewire/provider-litellm/internal/controller/providerconfig"
)

// Setup creates all controllers with the supplied logger and adds them to
// the supplied manager.
func Setup(mgr ctrl.Manager, o controller.Options) error {
	for _, setup := range []func(ctrl.Manager, controller.Options) error{
		credential.Setup,
		key.Setup,
		mcpserver.Setup,
		model.Setup,
		organization.Setup,
		organizationmember.Setup,
		organizationmemberadd.Setup,
		team.Setup,
		teammember.Setup,
		teammemberadd.Setup,
		vectorstore.Setup,
		providerconfig.Setup,
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
		mcpserver.SetupGated,
		model.SetupGated,
		organization.SetupGated,
		organizationmember.SetupGated,
		organizationmemberadd.SetupGated,
		team.SetupGated,
		teammember.SetupGated,
		teammemberadd.SetupGated,
		vectorstore.SetupGated,
		providerconfig.SetupGated,
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
		mcpserver.SetupWebhookWithManager,
		model.SetupWebhookWithManager,
		organization.SetupWebhookWithManager,
		organizationmember.SetupWebhookWithManager,
		organizationmemberadd.SetupWebhookWithManager,
		team.SetupWebhookWithManager,
		teammember.SetupWebhookWithManager,
		teammemberadd.SetupWebhookWithManager,
		vectorstore.SetupWebhookWithManager,
		providerconfig.SetupWebhookWithManager,
	} {
		if err := setup(mgr); err != nil {
			return err
		}
	}
	return nil
}
