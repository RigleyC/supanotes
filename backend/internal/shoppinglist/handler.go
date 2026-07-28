package shoppinglist

import (
	"errors"
	"net/http"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/labstack/echo/v4"
)

type AddItemRequest struct {
	Item string `json:"item"`
}

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) AddItem(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}
	var req AddItemRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}
	if err := h.svc.AddItem(c.Request().Context(), userID, req.Item); err != nil {
		status := http.StatusInternalServerError
		code := "internal_error"
		message := "não foi possível adicionar o item"
		switch {
		case errors.Is(err, ErrEmptyItem):
			status, code, message = http.StatusBadRequest, "empty_item", "o item não pode estar vazio"
		case errors.Is(err, ErrShoppingNotFound):
			status, code, message = http.StatusNotFound, "shopping_list_not_found", "a nota Lista de compras não existe"
		case errors.Is(err, ErrShoppingAmbiguous):
			status, code, message = http.StatusConflict, "shopping_list_ambiguous", "há mais de uma nota Lista de compras"
		}
		return c.JSON(status, map[string]string{"error": code, "message": message})
	}
	return c.JSON(http.StatusCreated, map[string]string{"message": "item adicionado à Lista de compras"})
}
