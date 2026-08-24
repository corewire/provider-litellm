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

package config

import (
	ujconfig "github.com/crossplane/upjet/v2/pkg/config"
)

// ExternalNameConfigs is the map of Terraform resource names to external name
// configurations. Every resource that should be exposed as a Crossplane managed
// resource must appear here.
var ExternalNameConfigs = map[string]ujconfig.ExternalName{
	// litellm_model is identified by model_id returned by the API on create.
	"litellm_model": ujconfig.IdentifierFromProvider,

	// litellm_team is identified by team_id returned by the API on create.
	"litellm_team": ujconfig.IdentifierFromProvider,

	// litellm_team_member is identified by a composite of team_id/user_id.
	"litellm_team_member": ujconfig.IdentifierFromProvider,

	// litellm_team_member_add manages the add operation of a team member.
	"litellm_team_member_add": ujconfig.IdentifierFromProvider,

	// litellm_organization is identified by organization_id.
	"litellm_organization": ujconfig.IdentifierFromProvider,

	// litellm_organization_member manages organization membership.
	"litellm_organization_member": ujconfig.IdentifierFromProvider,

	// litellm_key is identified by the key value returned on create.
	"litellm_key": ujconfig.IdentifierFromProvider,

	// litellm_credential stores credentials and is identified by credential_name.
	"litellm_credential": ujconfig.IdentifierFromProvider,

	// litellm_mcp_server manages Model Context Protocol servers.
	"litellm_mcp_server": ujconfig.IdentifierFromProvider,

	// litellm_vector_store manages vector store configurations.
	"litellm_vector_store": ujconfig.IdentifierFromProvider,
}

// ExternalNameConfigured returns the list of Terraform resource names that have
// external name configurations, i.e. which resources are included in the
// Crossplane provider.
func ExternalNameConfigured() []string {
	l := make([]string, len(ExternalNameConfigs))
	i := 0
	for name := range ExternalNameConfigs {
		// Need every item only once; no need to sort.
		l[i] = name
		i++
	}
	return l
}

// ExternalNameConfigurations applies the external name configs to each resource
// based on ExternalNameConfigs. Each resource in the list is configured with the
// associated ExternalName config.
func ExternalNameConfigurations() ujconfig.ResourceOption {
	return func(r *ujconfig.Resource) {
		if e, ok := ExternalNameConfigs[r.Name]; ok {
			r.ExternalName = e
		}
	}
}
