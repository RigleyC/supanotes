package mcpapp

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/shares"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func addSharingAndSettingsTools(server *mcp.Server, security SecurityStore, sharesSvc *shares.Service, settingsSvc *settings.Service) {
	addTool(server, security, &mcp.Tool{Name: toolListNoteShares, Description: "List shares for a note", InputSchema: idParamSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if err := requireReadScope(ctx); err != nil {
			return asError(err)
		}
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
		}
		args, err := decodeToolArgs[idToolArgs](request)
		if err != nil {
			return asError(err)
		}
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		noteIDValue, err := toolUUID(args.ID, "id")
		if err != nil {
			return asError(err)
		}
		noteID, err := uid.UUIDFromString(noteIDValue)
		if err != nil {
			return asError(err)
		}
		result, err := sharesSvc.ListNoteShares(ctx, userID, noteID)
		if err != nil {
			return asError(err)
		}
		return asTextResult(result)
	})
	shareSchema := map[string]any{"type": "object", "properties": map[string]any{"note_id": map[string]any{"type": "string"}, "email": map[string]any{"type": "string"}, "permission": map[string]any{"type": "string", "enum": []any{"view", "edit"}}, "confirmation_id": map[string]any{"type": "string"}}, "required": []any{"note_id", "email", "permission"}}
	addTool(server, security, &mcp.Tool{Name: toolShareNote, Description: "Share a note with a user", InputSchema: shareSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
		}
		args, err := decodeToolArgs[shareNoteToolArgs](request)
		if err != nil {
			return asError(err)
		}
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		noteIDValue, err := toolUUID(args.NoteID, "note_id")
		if err != nil {
			return asError(err)
		}
		noteID, err := uid.UUIDFromString(noteIDValue)
		if err != nil {
			return asError(err)
		}
		email, err := requiredToolString(args.Email, "email")
		if err != nil {
			return asError(err)
		}
		permission, err := toolPermission(args.Permission)
		if err != nil {
			return asError(err)
		}
		if err := requireWriteScope(ctx); err != nil {
			return asError(err)
		}
		confirmationLease, err := requireConfirmation(ctx, security, request, toolShareNote, "note:"+noteID.String())
		if err != nil {
			return asError(err)
		}
		if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
			return asError(replayErr)
		} else if ok {
			return replay, nil
		}
		result, err := finishConfirmationMutation(ctx, confirmationLease, func(ctx context.Context, tx pgx.Tx) (any, error) {
			return sharesSvc.ShareNoteInTransaction(ctx, tx, userID, noteID, email, permission)
		})
		if err != nil {
			return asError(err)
		}
		return asTextResult(result)
	})
	removeSchema := map[string]any{"type": "object", "properties": map[string]any{"note_id": map[string]any{"type": "string"}, "user_id": map[string]any{"type": "string"}, "confirmation_id": map[string]any{"type": "string"}}, "required": []any{"note_id", "user_id"}}
	addTool(server, security, &mcp.Tool{Name: toolRemoveNoteShare, Description: "Remove a note share", InputSchema: removeSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
		}
		args, err := decodeToolArgs[removeNoteShareToolArgs](request)
		if err != nil {
			return asError(err)
		}
		ownerID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		noteIDValue, err := toolUUID(args.NoteID, "note_id")
		if err != nil {
			return asError(err)
		}
		noteID, err := uid.UUIDFromString(noteIDValue)
		if err != nil {
			return asError(err)
		}
		targetIDValue, err := toolUUID(args.UserID, "user_id")
		if err != nil {
			return asError(err)
		}
		targetID, err := uid.UUIDFromString(targetIDValue)
		if err != nil {
			return asError(err)
		}
		if err := requireWriteScope(ctx); err != nil {
			return asError(err)
		}
		confirmationLease, err := requireConfirmation(ctx, security, request, toolRemoveNoteShare, "note:"+noteID.String()+"/user:"+targetID.String())
		if err != nil {
			return asError(err)
		}
		if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
			return asError(replayErr)
		} else if ok {
			return replay, nil
		}
		result, err := finishConfirmationMutation(ctx, confirmationLease, func(ctx context.Context, tx pgx.Tx) (any, error) {
			if err := sharesSvc.DeleteNoteShareInTransaction(ctx, tx, ownerID, noteID, targetID); err != nil {
				return nil, err
			}
			return "deleted", nil
		})
		if err != nil {
			return asError(err)
		}
		return asTextResult(result)
	})
	addTool(server, security, &mcp.Tool{Name: toolGetUserSettings, Description: "Get current user settings", InputSchema: noParamSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if err := requireReadScope(ctx); err != nil {
			return asError(err)
		}
		if settingsSvc == nil {
			return asError(fmt.Errorf("settings service is not configured"))
		}
		if _, err := decodeToolArgs[emptyToolArgs](request); err != nil {
			return asError(err)
		}
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		result, err := settingsSvc.Get(ctx, userID)
		if err != nil {
			return asError(err)
		}
		return asTextResult(result)
	})
	settingsSchema := map[string]any{"type": "object", "properties": map[string]any{"timezone": map[string]any{"type": "string"}, "preferences": map[string]any{"type": "object"}}}
	addTool(server, security, &mcp.Tool{Name: toolUpdateUserSettings, Description: "Update supported user settings", InputSchema: settingsSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if err := requireWriteScope(ctx); err != nil {
			return asError(err)
		}
		if settingsSvc == nil {
			return asError(fmt.Errorf("settings service is not configured"))
		}
		args, err := decodeToolArgs[updateSettingsToolArgs](request)
		if err != nil {
			return asError(err)
		}
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		prefs := args.Preferences
		if prefs == nil {
			prefs = map[string]any{}
		}
		result, err := settingsSvc.Update(ctx, userID, dto.UpdateSettingsRequest{Timezone: args.Timezone, Preferences: prefs})
		if err != nil {
			return asError(err)
		}
		return asTextResult(result)
	})
}
