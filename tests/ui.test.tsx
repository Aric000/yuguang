// @vitest-environment jsdom
import { afterEach, expect, test } from 'vitest';
import { act, cleanup, render, screen, fireEvent, waitFor } from '@testing-library/react';
import { previewBridge } from '../src/preview';
import { App } from '../src/main';
afterEach(cleanup);
test('match selection and simple preference retain the compact workflow', async () => {
  const bridge = previewBridge();
  render(<App bridge={bridge}/>);
  await screen.findByRole('heading', { name:'文字直播' });
  expect(screen.getByText('102')).toBeTruthy();
  expect(screen.getByAltText('湖人队徽')).toBeTruthy();
  fireEvent.click(screen.getByRole('button',{ name:'设置' }));
  await screen.findByRole('heading',{ name:'偏好设置' });
  fireEvent.change(screen.getByLabelText('精简模式显示行数'),{ target:{ value:'3' } });
  await waitFor(() => expect(screen.getByLabelText('精简模式显示行数').getAttribute('aria-label')).toBeTruthy());
  fireEvent.click(screen.getByRole('switch',{ name:'启用简洁模式' }));
  await waitFor(() => expect(screen.queryByAltText('湖人队徽')).toBeNull());
  expect(await screen.findByRole('button', { name:'切换比赛' })).toBeTruthy();
  expect(document.querySelectorAll('.compact-line').length).toBe(3);
  await act(async () => { await bridge.command('select','demo-2'); });
  await waitFor(() => expect(screen.getByText('106 : 100')).toBeTruthy());
  expect(document.querySelector('.compact')).toBeTruthy();
});
test('non-demo browser launch does not manufacture a desktop bridge', () => { expect(window.yuguang).toBeUndefined(); });
