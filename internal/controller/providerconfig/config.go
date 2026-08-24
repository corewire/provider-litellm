/*
Copyright 2024 Corewire.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package providerconfig contains the ProviderConfig controller of the LiteLLM
// provider.
package providerconfig

import (
	"github.com/crossplane/crossplane-runtime/v2/pkg/errors"
	"github.com/crossplane/crossplane-runtime/v2/pkg/event"
	"github.com/crossplane/crossplane-runtime/v2/pkg/reconciler/providerconfig"
	"github.com/crossplane/crossplane-runtime/v2/pkg/resource"
	"github.com/crossplane/upjet/v2/pkg/controller"
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/corewire/provider-litellm/apis/v1beta1"
)

// Setup adds a controller that reconciles ProviderConfigs by accounting for
// their current usage.
func Setup(mgr ctrl.Manager, o controller.Options) error {
	name := providerconfig.ControllerName(v1beta1.ProviderConfigGroupKind)

	of := resource.ProviderConfigKinds{
		Config:    v1beta1.ProviderConfigGroupVersionKind,
		Usage:     v1beta1.ProviderConfigUsageGroupVersionKind,
		UsageList: v1beta1.ProviderConfigUsageListGroupVersionKind,
	}

	return ctrl.NewControllerManagedBy(mgr).
		Named(name).
		WithOptions(o.ForControllerRuntime()).
		For(&v1beta1.ProviderConfig{}).
		Watches(&v1beta1.ProviderConfigUsage{}, &resource.EnqueueRequestForProviderConfig{}).
		Complete(providerconfig.NewReconciler(mgr, of,
			providerconfig.WithLogger(o.Logger.WithValues("controller", name)),
			providerconfig.WithRecorder(event.NewAPIRecorder(mgr.GetEventRecorderFor(name))))) //nolint:staticcheck // event.NewAPIRecorder only accepts the deprecated record.EventRecorder
}

// SetupWebhookWithManager registers the conversion webhook for the
// ProviderConfig kind.
func SetupWebhookWithManager(mgr ctrl.Manager) error {
	if err := ctrl.NewWebhookManagedBy(mgr, &v1beta1.ProviderConfig{}).
		Complete(); err != nil {
		return errors.Wrap(err, "cannot register webhook for the kind v1beta1.ProviderConfig")
	}
	return nil
}

// SetupGated adds a controller that reconciles ProviderConfigs by accounting
// for their current usage once the required CRDs are established.
func SetupGated(mgr ctrl.Manager, o controller.Options) error {
	o.Gate.Register(func() {
		if err := Setup(mgr, o); err != nil {
			mgr.GetLogger().Error(err, "unable to setup reconcilers", "gvk", v1beta1.ProviderConfigGroupVersionKind.String())
		}
	}, v1beta1.ProviderConfigGroupVersionKind, v1beta1.ProviderConfigUsageGroupVersionKind)
	return nil
}
